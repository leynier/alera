import FlutterMacOS
import WebKit

extension AleraBrowserPlugin {
  func handlePageMethod(
    _ method: String,
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) throws {
    if method == "page.create" {
      try createPage(arguments: arguments, result: result)
      return
    }
    let pageID = try arguments.requiredString("pageId")
    guard let page = pages[pageID] else {
      if method == "page.close" {
        result(nil)
        return
      }
      throw BrowserMethodError("page_not_found", "The browser page does not exist.")
    }
    switch method {
    case "page.attach":
      try page.attach()
      result(nil)
    case "page.detach":
      page.detach()
      result(nil)
    case "page.setObscured":
      page.obscured = arguments.bool("obscured")
      page.updateSurfaceVisibility()
      result(nil)
    case "page.setBounds":
      try page.setBounds(
        x: arguments.double("x"),
        y: arguments.double("y"),
        width: arguments.double("width"),
        height: arguments.double("height"),
        scale: arguments.double("scale", default: 1)
      )
      result(nil)
    case "page.adoptTransient":
      let profileID = try arguments.requiredString("profileId")
      guard page.transient, page.profile.id == profileID else {
        throw BrowserMethodError(
          "invalid_transient_page",
          "The transient popup does not match the requested profile."
        )
      }
      page.adopted = true
      result(nil)
    case "page.promoteTransient":
      guard !page.transient || page.adopted else {
        throw BrowserMethodError(
          "transient_not_adopted",
          "The transient popup must be adopted before it is promoted."
        )
      }
      page.transient = false
      result(nil)
    case "page.close":
      closePage(pageID)
      result(nil)
    case "page.loadUrl":
      try loadURL(arguments: arguments, page: page)
      result(nil)
    case "page.currentUrl":
      result(page.webView.url?.absoluteString)
    case "page.title":
      result(page.webView.title)
    case "page.canGoBack":
      result(page.webView.canGoBack)
    case "page.canGoForward":
      result(page.webView.canGoForward)
    case "page.goBack":
      page.webView.goBack()
      result(nil)
    case "page.goForward":
      page.webView.goForward()
      result(nil)
    case "page.reload":
      page.webView.reload()
      result(nil)
    case "page.stop":
      page.webView.stopLoading()
      result(nil)
    case "page.evaluateJavaScript":
      try evaluateJavaScript(arguments: arguments, page: page, result: result)
    case "page.upload":
      try uploadFiles(arguments: arguments, page: page, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func createPage(arguments: [String: Any], result: @escaping FlutterResult) throws {
    let id = arguments.optionalString("id") ?? UUID().uuidString.lowercased()
    try validateIdentifier(id, kind: "page", maximum: 128)
    guard pages[id] == nil else {
      throw BrowserMethodError("duplicate_page", "The browser page already exists.")
    }
    let profileID = arguments.optionalString("profileId") ?? "default"
    let selectedProfile = try profile(profileID)
    let openerID = arguments.optionalString("openerPageId")
    if let openerID {
      guard let opener = pages[openerID], opener.profile.id == profileID else {
        throw BrowserMethodError(
          "invalid_opener",
          "The opener page must exist in the same browser profile."
        )
      }
    }
    let page = BrowserPage(
      owner: self,
      id: id,
      profile: selectedProfile,
      openerPageID: openerID,
      transient: arguments.bool("transient")
    )
    if let userAgent = arguments.optionalString("userAgent") {
      page.webView.customUserAgent = userAgent
    }
    pages[id] = page
    if let initialURL = arguments.optionalString("initialUrl") {
      do {
        try page.webView.load(URLRequest(url: validatedBrowserURL(initialURL)))
      } catch {
        pages.removeValue(forKey: id)
        page.close()
        throw error
      }
    }
    var value: [String: Any] = ["id": id]
    if let title = page.webView.title { value["title"] = title }
    result(value)
  }

  private func loadURL(arguments: [String: Any], page: BrowserPage) throws {
    let url = try validatedBrowserURL(arguments.requiredString("url"))
    var request = URLRequest(url: url)
    if let headers = arguments["headers"] as? [String: String] {
      for (name, value) in headers {
        guard
          !name.isEmpty,
          !name.contains("\r"),
          !name.contains("\n"),
          !value.contains("\r"),
          !value.contains("\n")
        else {
          throw BrowserMethodError("invalid_header", "A browser request header is invalid.")
        }
        request.setValue(value, forHTTPHeaderField: name)
      }
    }
    page.webView.load(request)
  }

  private func evaluateJavaScript(
    arguments: [String: Any],
    page: BrowserPage,
    result: @escaping FlutterResult
  ) throws {
    let script = try arguments.requiredString("script")
    page.webView.evaluateJavaScript(script) { value, error in
      if let error {
        result(BrowserMethodError("javascript_failed", error.localizedDescription).asFlutterError)
      } else {
        result(value)
      }
    }
  }

  private func uploadFiles(
    arguments: [String: Any],
    page: BrowserPage,
    result: @escaping FlutterResult
  ) throws {
    guard page.pendingUploadResult == nil else {
      throw BrowserMethodError("upload_in_progress", "A file upload is already in progress.")
    }
    let elementRef = try arguments.requiredString("elementRef")
    guard
      let paths = arguments["filePaths"] as? [String],
      !paths.isEmpty
    else {
      throw BrowserMethodError("invalid_upload", "At least one file path is required.")
    }
    let urls = try paths.map { path -> URL in
      guard NSString(string: path).isAbsolutePath else {
        throw BrowserMethodError("invalid_upload", "Every upload path must be absolute.")
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      var isDirectory: ObjCBool = false
      guard
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        !isDirectory.boolValue,
        FileManager.default.isReadableFile(atPath: url.path)
      else {
        throw BrowserMethodError("invalid_upload", "Every upload file must exist and be readable.")
      }
      return url
    }
    let reference = try javascriptLiteral(elementRef)
    let script = """
      (() => {
        const state = window.__aleraBrowserAutomation;
        const entry = state?.elements?.get(\(reference));
        if (!entry?.element?.isConnected) return JSON.stringify({ok:false,code:'stale_element'});
        if (JSON.stringify(state.signatureFor(entry.element)) !== JSON.stringify(entry.signature)) {
          return JSON.stringify({ok:false,code:'stale_element'});
        }
        if (!(entry.element instanceof HTMLInputElement) || entry.element.type !== 'file') {
          return JSON.stringify({ok:false,code:'wrong_element_type'});
        }
        entry.element.click();
        return JSON.stringify({ok:true});
      })()
      """
    page.pendingUploadURLs = urls
    page.pendingUploadResult = result
    page.webView.evaluateJavaScript(script) { [weak page] value, error in
      guard let page else { return }
      if let error {
        page.finishUpload(
          error: BrowserMethodError("upload_failed", error.localizedDescription)
        )
        return
      }
      guard
        let text = value as? String,
        let data = text.data(using: .utf8),
        let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        response["ok"] as? Bool == true
      else {
        page.finishUpload(
          error: BrowserMethodError("upload_failed", "The file input is stale or invalid.")
        )
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak page] in
        guard let page, page.pendingUploadResult != nil else { return }
        page.finishUpload(
          error: BrowserMethodError(
            "upload_chooser_unavailable",
            "WebKit did not open the requested file input."
          )
        )
      }
    }
  }

  func closePage(_ pageID: String) {
    guard let page = pages.removeValue(forKey: pageID) else { return }
    cancelDecisions(forPage: pageID)
    cancelDownloads(forPage: pageID)
    page.close()
  }

  func page(_ id: String) throws -> BrowserPage {
    guard let page = pages[id], !page.closed else {
      throw BrowserMethodError("page_not_found", "The browser page does not exist.")
    }
    return page
  }
}

extension BrowserPage {
  func finishUpload(error: BrowserMethodError? = nil) {
    guard let result = pendingUploadResult else { return }
    pendingUploadResult = nil
    pendingUploadURLs = nil
    result(error?.asFlutterError)
  }
}

func validatedBrowserURL(_ value: String) throws -> URL {
  guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
    throw BrowserMethodError("invalid_url", "The browser URL is invalid.")
  }
  let allowed = scheme == "http" || scheme == "https" || value == "about:blank"
  guard allowed, scheme == "about" || url.host != nil else {
    throw BrowserMethodError("unsupported_url", "Only HTTP, HTTPS, and about:blank are supported.")
  }
  return url
}
