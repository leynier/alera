import FlutterMacOS
import WebKit

extension AleraBrowserPlugin {
  func handleCookieImportMethod(
    _ method: String,
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) throws {
    switch method {
    case "cookieImport.probe":
      importQueue.async { [weak self] in
        guard let self else { return }
        let statuses = cookieImportStatuses()
        DispatchQueue.main.async { result(statuses) }
      }
    case "cookieImport.run":
      let profileID = try arguments.requiredString("profileId")
      let source = try arguments.requiredString("source")
      let selectedProfile = try profile(profileID)
      guard source == "manualJson" || Self.requiredImportSources.contains(source) else {
        result(importResult(source: source, profileID: profileID, outcome: "unsupported"))
        return
      }
      guard !activeCookieImports.contains(profileID) else {
        throw BrowserMethodError("import_in_progress", "This profile is already importing cookies.")
      }
      guard !pages.values.contains(where: { $0.profile.id == profileID }) else {
        result(
          importResult(
            source: source,
            profileID: profileID,
            outcome: "failed",
            detailCode: "profile_in_use"
          )
        )
        return
      }
      activeCookieImports.insert(profileID)
      let sourceProfileName = arguments.optionalString("sourceProfileName")
      let manualJSON = arguments.optionalString("json")
      importQueue.async { [weak self] in
        guard let self else { return }
        do {
          let batch = try self.loadImportBatch(
            source: source,
            sourceProfileName: sourceProfileName,
            manualJSON: manualJSON
          )
          DispatchQueue.main.async {
            self.commitImport(
              batch,
              source: source,
              profile: selectedProfile,
              result: result
            )
          }
        } catch let error as BrowserImportError {
          DispatchQueue.main.async {
            self.activeCookieImports.remove(profileID)
            result(
              self.importResult(
                source: source,
                profileID: profileID,
                outcome: error.outcome,
                detailCode: error.detailCode
              )
            )
          }
        } catch {
          DispatchQueue.main.async {
            self.activeCookieImports.remove(profileID)
            result(
              self.importResult(
                source: source,
                profileID: profileID,
                outcome: "failed",
                detailCode: "native_import_failed"
              )
            )
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func cookieImportStatuses() -> [[String: Any]] {
    var values = ChromiumImportSource.supported.map { source in
      importStatus(source.id, profiles: source.cookieProfiles())
    }
    values.append(
      importStatus("firefox", profiles: firefoxCookieProfiles())
    )
    values.append(
      importStatus("safari", profiles: safariCookieProfiles())
    )
    values.append([
      "source": "manualJson",
      "supported": true,
      "available": true,
    ])
    let order = Self.requiredImportSources + ["manualJson"]
    return values.sorted {
      (order.firstIndex(of: $0["source"] as? String ?? "") ?? Int.max)
        < (order.firstIndex(of: $1["source"] as? String ?? "") ?? Int.max)
    }
  }

  private func importStatus(
    _ source: String,
    profiles: [BrowserImportProfileLocation]
  ) -> [String: Any] {
    let available = !profiles.isEmpty
    var value: [String: Any] = [
      "source": source,
      "supported": true,
      "available": available,
      "profileNames": profiles.map(\.name),
    ]
    if !available { value["detailCode"] = "source_not_installed" }
    return value
  }

  private func loadImportBatch(
    source: String,
    sourceProfileName: String?,
    manualJSON: String?
  ) throws -> BrowserImportBatch {
    if source == "manualJson" {
      guard let manualJSON else {
        throw BrowserImportError("failed", "manual_json_required")
      }
      return try BrowserManualCookieImport.parse(manualJSON)
    }
    if let chromium = ChromiumImportSource.source(id: source) {
      let profile = try selectedBrowserImportProfile(
        chromium.cookieProfiles(),
        named: sourceProfileName
      )
      return try BrowserChromiumCookieImport.load(
        source: chromium,
        profile: profile
      )
    }
    if source == "firefox" {
      let profile = try selectedBrowserImportProfile(
        firefoxCookieProfiles(),
        named: sourceProfileName
      )
      return try BrowserFirefoxCookieImport.load(profile: profile)
    }
    if source == "safari" {
      let profile = try selectedBrowserImportProfile(
        safariCookieProfiles(),
        named: sourceProfileName
      )
      return try BrowserSafariCookieImport.load(profile: profile)
    }
    throw BrowserImportError("unsupported", "source_unsupported")
  }

  private func commitImport(
    _ batch: BrowserImportBatch,
    source: String,
    profile: BrowserProfile,
    result: @escaping FlutterResult
  ) {
    let store = profile.dataStore.httpCookieStore
    store.getAllCookies { baseline in
      self.setCookies(batch.cookies[...], in: store) {
        store.getAllCookies { committed in
          let committedByKey = Dictionary(
            committed.map { (BrowserCookieKey($0), $0) },
            uniquingKeysWith: { _, last in last }
          )
          let verified = batch.cookies.allSatisfy { desired in
            committedByKey[BrowserCookieKey(desired)]
              .map { browserCookiesEquivalent($0, desired) } == true
          }
          if verified {
            self.activeCookieImports.remove(profile.id)
            result(
              self.importResult(
                source: source,
                profileID: profile.id,
                outcome: batch.skipped > 0 ? "partiallyImported" : "imported",
                importedCount: batch.cookies.count,
                skippedCount: batch.skipped
              )
            )
          } else {
            self.rollbackImport(
              store: store,
              baseline: baseline,
              source: source,
              profileID: profile.id,
              result: result
            )
          }
        }
      }
    }
  }

  private func rollbackImport(
    store: WKHTTPCookieStore,
    baseline: [HTTPCookie],
    source: String,
    profileID: String,
    result: @escaping FlutterResult
  ) {
    store.getAllCookies { current in
      self.deleteCookies(current[...], from: store) {
        self.setCookies(baseline[...], in: store) {
          store.getAllCookies { restored in
            let restoredByKey = Dictionary(
              restored.map { (BrowserCookieKey($0), $0) },
              uniquingKeysWith: { _, last in last }
            )
            let restoredExactly =
              restored.count == baseline.count
              && baseline.allSatisfy { expected in
                restoredByKey[BrowserCookieKey(expected)]
                  .map { browserCookiesEquivalent($0, expected) } == true
              }
            self.activeCookieImports.remove(profileID)
            result(
              self.importResult(
                source: source,
                profileID: profileID,
                outcome: "failed",
                detailCode: restoredExactly
                  ? "commit_verification_failed"
                  : "rollback_verification_failed"
              )
            )
          }
        }
      }
    }
  }

  private func importResult(
    source: String,
    profileID: String,
    outcome: String,
    importedCount: Int = 0,
    skippedCount: Int = 0,
    detailCode: String? = nil
  ) -> [String: Any] {
    var value: [String: Any] = [
      "source": source,
      "profileId": profileID,
      "outcome": outcome,
      "importedCount": importedCount,
      "skippedCount": skippedCount,
    ]
    if let detailCode { value["detailCode"] = detailCode }
    return value
  }
}
