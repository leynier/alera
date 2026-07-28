import Security
import WebKit

final class PendingBrowserDecision {
  enum Kind {
    case permission((WKPermissionDecision) -> Void)
    case tls(
      SecTrust,
      (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    )
    case popup(String)
    case download((URL?) -> Void)
  }

  weak var owner: AleraBrowserPlugin?
  let id: String
  let pageID: String
  let kind: Kind
  var timeout: DispatchWorkItem?

  init(owner: AleraBrowserPlugin, id: String, pageID: String, kind: Kind) {
    self.owner = owner
    self.id = id
    self.pageID = pageID
    self.kind = kind
  }

  func cancelWithDefault() {
    timeout?.cancel()
    timeout = nil
    switch kind {
    case .permission(let completion):
      completion(.deny)
    case .tls(_, let completion):
      completion(.cancelAuthenticationChallenge, nil)
    case .popup(let transientPageID):
      owner?.closePage(transientPageID)
    case .download(let completion):
      completion(nil)
    }
  }
}

extension AleraBrowserPlugin {
  private static var decisionTimeout: DispatchTimeInterval { .seconds(30) }

  func requestPermissionDecision(
    page: BrowserPage,
    origin: String,
    resources: [String],
    completion: @escaping (WKPermissionDecision) -> Void
  ) {
    let decision = addDecision(
      pageID: page.id,
      kind: .permission(completion)
    )
    emit([
      "type": "permissionRequest",
      "decisionId": decision.id,
      "pageId": page.id,
      "origin": origin,
      "resources": resources,
    ])
  }

  func requestTLSDecision(
    page: BrowserPage,
    trust: SecTrust,
    description: String?,
    completion:
      @escaping (
        URLSession.AuthChallengeDisposition,
        URLCredential?
      ) -> Void
  ) {
    let decision = addDecision(pageID: page.id, kind: .tls(trust, completion))
    var event: [String: Any] = [
      "type": "tlsRequest",
      "decisionId": decision.id,
      "pageId": page.id,
      "url": (page.lastRequestedMainFrameURL ?? page.webView.url)?.absoluteString ?? "",
    ]
    if let description { event["description"] = description }
    emit(event)
  }

  func createTransientPopup(
    opener: BrowserPage,
    configuration: WKWebViewConfiguration,
    navigationAction: WKNavigationAction
  ) -> WKWebView? {
    let suppliedStore = configuration.websiteDataStore
    let expectedStore = opener.profile.dataStore
    let sameStore: Bool
    if let suppliedID = suppliedStore.identifier, let expectedID = expectedStore.identifier {
      sameStore = suppliedID == expectedID
    } else {
      sameStore = suppliedStore === expectedStore
    }
    guard sameStore else { return nil }
    let id = UUID().uuidString.lowercased()
    let page = BrowserPage(
      owner: self,
      id: id,
      profile: opener.profile,
      openerPageID: opener.id,
      transient: true,
      configuration: configuration
    )
    pages[id] = page
    let decision = addDecision(pageID: opener.id, kind: .popup(id))
    emit([
      "type": "popupRequest",
      "decisionId": decision.id,
      "pageId": opener.id,
      "transientPageId": id,
      "profileId": opener.profile.id,
      "url": navigationAction.request.url?.absoluteString ?? "about:blank",
      "userInitiated": true,
      "trusted": true,
      "requiresOpener": true,
    ])
    return page.webView
  }

  func addDecision(
    pageID: String,
    kind: PendingBrowserDecision.Kind
  ) -> PendingBrowserDecision {
    let id = UUID().uuidString.lowercased()
    let decision = PendingBrowserDecision(
      owner: self,
      id: id,
      pageID: pageID,
      kind: kind
    )
    let work = DispatchWorkItem { [weak self, weak decision] in
      guard
        let self,
        let decision,
        decisions.removeValue(forKey: decision.id) != nil
      else {
        return
      }
      decision.cancelWithDefault()
    }
    decision.timeout = work
    decisions[id] = decision
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.decisionTimeout, execute: work)
    return decision
  }

  func resolveDecision(arguments: [String: Any]) throws {
    let id = try arguments.requiredString("decisionId")
    guard let pending = decisions.removeValue(forKey: id) else {
      throw BrowserMethodError(
        "decision_not_found", "The browser decision expired or was resolved.")
    }
    pending.timeout?.cancel()
    let choice: String
    do {
      choice = try arguments.requiredString("decision")
    } catch {
      pending.cancelWithDefault()
      throw error
    }
    switch pending.kind {
    case .permission(let completion):
      guard choice == "allow" || choice == "deny" else {
        completion(.deny)
        throw BrowserMethodError("invalid_decision", "The permission decision is invalid.")
      }
      completion(choice == "allow" ? .grant : .deny)
    case .tls(let trust, let completion):
      guard choice == "proceed" || choice == "cancel" else {
        completion(.cancelAuthenticationChallenge, nil)
        throw BrowserMethodError("invalid_decision", "The TLS decision is invalid.")
      }
      if choice == "proceed" {
        completion(.useCredential, URLCredential(trust: trust))
      } else {
        completion(.cancelAuthenticationChallenge, nil)
      }
    case .popup(let transientPageID):
      guard choice == "newPage" || choice == "deny" else {
        closePage(transientPageID)
        throw BrowserMethodError("invalid_decision", "The popup decision is invalid.")
      }
      if choice == "newPage" {
        let targetID = arguments.optionalString("targetPageId")
        guard
          targetID == transientPageID,
          let page = pages[transientPageID],
          page.transient,
          page.adopted
        else {
          closePage(transientPageID)
          throw BrowserMethodError(
            "invalid_popup_target",
            "The popup target must be the adopted transient page."
          )
        }
      } else {
        closePage(transientPageID)
      }
    case .download(let completion):
      guard choice == "accept" || choice == "deny" else {
        completion(nil)
        throw BrowserMethodError("invalid_decision", "The download decision is invalid.")
      }
      if choice == "accept" {
        do {
          let path = try arguments.requiredString("destinationPath")
          completion(try validatedDownloadDestination(path))
        } catch {
          completion(nil)
          throw error
        }
      } else {
        completion(nil)
      }
    }
  }

  func cancelDecisions(forPage pageID: String) {
    let matches = decisions.values.filter { decision in
      if decision.pageID == pageID { return true }
      if case .popup(let transientID) = decision.kind {
        return transientID == pageID
      }
      return false
    }
    for decision in matches {
      decisions.removeValue(forKey: decision.id)
      decision.cancelWithDefault()
    }
  }
}

private func validatedDownloadDestination(_ path: String) throws -> URL {
  guard NSString(string: path).isAbsolutePath else {
    throw BrowserMethodError("invalid_destination", "The download destination must be absolute.")
  }
  let url = URL(fileURLWithPath: path).standardizedFileURL
  let parent = url.deletingLastPathComponent()
  var isDirectory: ObjCBool = false
  guard
    FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
    isDirectory.boolValue,
    FileManager.default.isWritableFile(atPath: parent.path)
  else {
    throw BrowserMethodError("invalid_destination", "The download directory is not writable.")
  }
  var info = stat()
  guard lstat(url.path, &info) != 0 && errno == ENOENT else {
    throw BrowserMethodError("destination_exists", "The download destination already exists.")
  }
  return url
}
