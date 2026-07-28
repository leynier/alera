import AppKit
import FlutterMacOS
import WebKit
import XCTest

@testable import alera_browser

final class BrowserImportTests: XCTestCase {
  func testStableProfileUUIDIsDeterministicAndNamespaced() {
    XCTAssertEqual(stableProfileUUID("work"), stableProfileUUID("work"))
    XCTAssertNotEqual(stableProfileUUID("work"), stableProfileUUID("other"))
    XCTAssertNotEqual(stableProfileUUID("default"), UUID())
  }

  func testManualJSONPreservesFullCookieAttributes() throws {
    let json = """
      {
        "cookies": [{
          "name": "session",
          "value": "secret",
          "domain": ".example.com",
          "path": "/account",
          "expiresUtc": 4102444800000,
          "secure": true,
          "httpOnly": true,
          "sameSite": "Strict",
          "session": false
        }]
      }
      """
    let batch = try BrowserManualCookieImport.parse(json)
    XCTAssertEqual(batch.skipped, 0)
    XCTAssertEqual(batch.cookies.count, 1)
    let cookie = try XCTUnwrap(batch.cookies.first)
    XCTAssertEqual(cookie.name, "session")
    XCTAssertEqual(cookie.value, "secret")
    XCTAssertEqual(cookie.domain, ".example.com")
    XCTAssertEqual(cookie.path, "/account")
    XCTAssertTrue(cookie.isSecure)
    XCTAssertTrue(cookie.isHTTPOnly)
    XCTAssertEqual(cookie.sameSitePolicy, .sameSiteStrict)
    XCTAssertFalse(cookie.isSessionOnly)
  }

  func testManualJSONRejectsWholeMalformedBatch() {
    let json = """
      [
        {"name":"valid","value":"1","domain":"example.com"},
        {"name":"missing-domain","value":"2"}
      ]
      """
    XCTAssertThrowsError(try BrowserManualCookieImport.parse(json)) { error in
      XCTAssertEqual((error as? BrowserImportError)?.detailCode, "manual_json_invalid_cookie")
    }
  }

  func testManualJSONDeduplicatesByCookieIdentity() throws {
    let json = """
      [
        {"name":"a","value":"old","domain":"example.com","path":"/"},
        {"name":"a","value":"new","domain":"example.com","path":"/"}
      ]
      """
    let batch = try BrowserManualCookieImport.parse(json)
    XCTAssertEqual(batch.cookies.count, 1)
    XCTAssertEqual(batch.cookies.first?.value, "new")
    XCTAssertEqual(batch.skipped, 1)
  }

  func testManualJSONAcceptsUnspecifiedSameSite() throws {
    let batch = try BrowserManualCookieImport.parse(
      """
      [{"name":"a","value":"1","domain":"example.com","sameSite":"unspecified"}]
      """
    )
    XCTAssertNil(batch.cookies.first?.sameSitePolicy)
  }

  func testManualJSONRejectsOversizedPayload() {
    let payload = String(
      repeating: " ",
      count: 16 * 1024 * 1024 + 1
    )
    XCTAssertThrowsError(try BrowserManualCookieImport.parse(payload)) { error in
      XCTAssertEqual(
        (error as? BrowserImportError)?.detailCode,
        "manual_json_too_large"
      )
    }
  }

  func testSourceProfileSelectionRejectsUnknownAndAmbiguousNames() throws {
    let profiles = [
      BrowserImportProfileLocation(
        name: "Default",
        fileURL: URL(fileURLWithPath: "/one/Cookies")
      ),
      BrowserImportProfileLocation(
        name: "Profile 1",
        fileURL: URL(fileURLWithPath: "/two/Cookies")
      ),
      BrowserImportProfileLocation(
        name: "Default",
        fileURL: URL(fileURLWithPath: "/three/Cookies")
      ),
    ]
    XCTAssertEqual(
      try selectedBrowserImportProfile(
        profiles,
        named: "Profile 1"
      ).fileURL.path,
      "/two/Cookies"
    )
    for (name, detail) in [
      ("Missing", "source_profile_not_found"),
      ("Default", "source_profile_ambiguous"),
      ("", "source_profile_required"),
    ] {
      XCTAssertThrowsError(
        try selectedBrowserImportProfile(profiles, named: name)
      ) { error in
        XCTAssertEqual(
          (error as? BrowserImportError)?.detailCode,
          detail
        )
      }
    }
  }

  func testSourceProfilesUseVisibleNamesWithSafeFallbacks() {
    let localState = Data(
      #"{"profile":{"info_cache":{"Default":{"name":"Personal"}}}}"#.utf8
    )
    XCTAssertEqual(
      chromiumProfileDisplayName(
        localStateData: localState,
        directory: "Default"
      ),
      "Personal"
    )
    XCTAssertEqual(
      chromiumProfileDisplayName(
        localStateData: Data("invalid".utf8),
        directory: "Profile 1"
      ),
      "Profile 1"
    )
    XCTAssertEqual(
      firefoxProfileDisplayName("abc123.default-release"),
      "default-release"
    )
  }

  func testSafariParserRejectsTruncatedPageTable() {
    XCTAssertThrowsError(
      try BrowserSafariCookieImport.parse(Data("cook\u{0}\u{0}\u{0}\u{1}".utf8))
    ) { error in
      XCTAssertEqual((error as? BrowserImportError)?.detailCode, "safari_cookie_file_invalid")
    }
  }

  func testRequiredMacOSSourceMatrixIsExact() {
    XCTAssertEqual(
      AleraBrowserPlugin.requiredImportSources,
      ["chrome", "edge", "arc", "brave", "comet", "helium", "firefox", "safari"]
    )
  }

  @MainActor
  func testCapabilityProbePublishesTheCompleteFailClosedMatrix() throws {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let plugin = AleraBrowserPlugin(hostView: host)
    var response: Any?
    plugin.handle(FlutterMethodCall(methodName: "probe", arguments: nil)) {
      response = $0
    }
    let capabilities = try XCTUnwrap(response as? [String: Any])
    XCTAssertEqual(capabilities["engine"] as? String, "wkWebView")
    let implemented = [
      "engineAvailable",
      "pageSurface",
      "isolatedProfiles",
      "ephemeralProfiles",
      "deterministicPageClose",
      "navigation",
      "navigationEvents",
      "javascript",
      "fullCookies",
      "permissionCallbacks",
      "tlsCallbacks",
      "popupCallbacks",
      "downloadCallbacks",
      "domSnapshot",
      "domActions",
      "nativeFileUpload",
      "viewportScreenshot",
      "fullPageScreenshot",
      "pdf",
      "flutterOverlayOcclusion",
      "atomicCookieImport",
      "manualJsonCookieImport",
    ]
    for capability in implemented {
      XCTAssertEqual(capabilities[capability] as? Bool, true, capability)
    }
    XCTAssertEqual(capabilities["crossOriginFrameAutomation"] as? Bool, false)
    XCTAssertEqual(capabilities["trustedInputEvents"] as? Bool, false)
    XCTAssertEqual(
      capabilities["nativeCookieImportSources"] as? [String],
      AleraBrowserPlugin.requiredImportSources
    )
  }

  @MainActor
  func testWKWebViewSurfaceLifecycleIsDeterministic() throws {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let plugin = AleraBrowserPlugin(hostView: host)
    let profile = BrowserProfile(id: "surface-test", storage: "ephemeral", isDefault: false)
    let page = BrowserPage(
      owner: plugin,
      id: "surface-test",
      profile: profile,
      openerPageID: nil,
      transient: false
    )
    try page.setBounds(x: 12, y: 24, width: 640, height: 480, scale: 2)
    try page.attach()
    XCTAssertTrue(page.webView.superview === host)
    XCTAssertFalse(page.webView.isHidden)
    page.obscured = true
    page.updateSurfaceVisibility()
    XCTAssertTrue(page.webView.isHidden)
    page.detach()
    XCTAssertNil(page.webView.superview)
    page.close()
    XCTAssertTrue(page.closed)
  }

  @MainActor
  func testNavigationFinishedPublishesHistoryState() throws {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let plugin = AleraBrowserPlugin(hostView: host)
    let profile = BrowserProfile(id: "navigation-test", storage: "ephemeral", isDefault: false)
    let page = BrowserPage(
      owner: plugin,
      id: "navigation-test",
      profile: profile,
      openerPageID: nil,
      transient: false
    )
    var response: [String: Any]?
    plugin.eventSink = { event in
      response = event as? [String: Any]
    }
    page.webView(page.webView, didFinish: nil)
    let event = try XCTUnwrap(response)
    XCTAssertEqual(event["type"] as? String, "navigationFinished")
    XCTAssertEqual(event["canGoBack"] as? Bool, false)
    XCTAssertEqual(event["canGoForward"] as? Bool, false)
  }

  @MainActor
  func testInvalidDecisionCompletesFailClosed() throws {
    let plugin = AleraBrowserPlugin(hostView: NSView())
    var permission: WKPermissionDecision?
    let permissionDecision = plugin.addDecision(
      pageID: "decision-test",
      kind: .permission { permission = $0 }
    )
    XCTAssertThrowsError(
      try plugin.resolveDecision(arguments: ["decisionId": permissionDecision.id])
    )
    XCTAssertEqual(permission, .deny)

    var downloadCompleted = false
    var destination: URL?
    let downloadDecision = plugin.addDecision(
      pageID: "decision-test",
      kind: .download {
        downloadCompleted = true
        destination = $0
      }
    )
    XCTAssertThrowsError(
      try plugin.resolveDecision(arguments: [
        "decisionId": downloadDecision.id,
        "decision": "accept",
        "destinationPath": "relative.txt",
      ])
    )
    XCTAssertTrue(downloadCompleted)
    XCTAssertNil(destination)
  }

  @MainActor
  func testWKCookieStoreRoundTripsSecurityAttributes() throws {
    let profile = BrowserProfile(id: "cookie-test", storage: "ephemeral", isDefault: false)
    let expected = try decodeBrowserCookie([
      "name": "native",
      "value": "value",
      "domain": "example.com",
      "path": "/",
      "secure": true,
      "httpOnly": true,
      "sameSite": "lax",
      "session": true,
    ])
    let completed = expectation(description: "WebKit cookie round trip")
    profile.dataStore.httpCookieStore.setCookie(expected) {
      profile.dataStore.httpCookieStore.getAllCookies { cookies in
        let actual = cookies.first { BrowserCookieKey($0) == BrowserCookieKey(expected) }
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual?.value, "value")
        XCTAssertEqual(actual?.isSecure, true)
        XCTAssertEqual(actual?.isHTTPOnly, true)
        XCTAssertEqual(actual?.sameSitePolicy, .sameSiteLax)
        completed.fulfill()
      }
    }
    wait(for: [completed], timeout: 10)
  }
}
