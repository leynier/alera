import AppKit
import XCTest

@testable import alera_browser

final class BrowserNavigationTests: XCTestCase {
  @MainActor
  func testNavigationCommitPublishesCommittedURL() throws {
    let plugin = AleraBrowserPlugin(hostView: NSView())
    let profile = BrowserProfile(
      id: "navigation-commit-test",
      storage: "ephemeral",
      isDefault: false
    )
    let page = BrowserPage(
      owner: plugin,
      id: "navigation-commit-test",
      profile: profile,
      openerPageID: nil,
      transient: false
    )
    var response: [String: Any]?
    plugin.eventSink = { event in
      response = event as? [String: Any]
    }

    page.webView(page.webView, didCommit: nil)

    let event = try XCTUnwrap(response)
    XCTAssertEqual(event["type"] as? String, "navigationCommitted")
    XCTAssertEqual(event["pageId"] as? String, "navigation-commit-test")
    XCTAssertEqual(event["url"] as? String, "about:blank")
  }

  func testTemporaryCertificateHostsMatchTheAppPolicy() {
    for host in [
      "localhost",
      "service.localhost",
      "service.local",
      "127.0.0.1",
      "10.4.2.1",
      "169.254.4.2",
      "172.31.8.9",
      "192.168.1.20",
      "::1",
      "0:0:0:0:0:0:0:1",
      "fe80::1",
      "febf::1",
    ] {
      XCTAssertTrue(isTemporaryLocalCertificateHost(host), host)
    }
    for host in [
      "example.com",
      "172.32.0.1",
      "192.169.1.1",
      "127.0.0.01",
      "::fe80",
      "fe80::not-ip",
      "fec0::1",
    ] {
      XCTAssertFalse(isTemporaryLocalCertificateHost(host), host)
    }
  }
}
