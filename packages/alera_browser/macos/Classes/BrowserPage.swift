import Cocoa
import FlutterMacOS
import WebKit

final class BrowserPage: NSObject, WKScriptMessageHandler {
  static let consoleHandlerName = "aleraBrowserConsole"

  weak var owner: AleraBrowserPlugin?
  let id: String
  let profile: BrowserProfile
  let openerPageID: String?
  var transient: Bool
  var adopted = false
  var attached = false
  var obscured = false
  var closed = false
  var surfaceBounds = NSRect.zero
  var lastRequestedMainFrameURL: URL?
  var pendingUploadURLs: [URL]?
  var pendingUploadResult: FlutterResult?
  var webView: WKWebView!
  var progressObservation: NSKeyValueObservation?
  var urlObservation: NSKeyValueObservation?

  init(
    owner: AleraBrowserPlugin,
    id: String,
    profile: BrowserProfile,
    openerPageID: String?,
    transient: Bool,
    configuration suppliedConfiguration: WKWebViewConfiguration? = nil
  ) {
    self.owner = owner
    self.id = id
    self.profile = profile
    self.openerPageID = openerPageID
    self.transient = transient
    super.init()

    let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
    if suppliedConfiguration == nil {
      configuration.websiteDataStore = profile.dataStore
    }
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    let contentController = WKUserContentController()
    contentController.addUserScript(
      WKUserScript(
        source: Self.consoleBridgeScript,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
      )
    )
    contentController.add(self, name: Self.consoleHandlerName)
    configuration.userContentController = contentController

    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.isHidden = true
    webView.allowsBackForwardNavigationGestures = true
    observePageState()
  }

  private func observePageState() {
    progressObservation = webView.observe(
      \.estimatedProgress,
      options: [.new]
    ) { [weak self] _, change in
      guard let self, let progress = change.newValue else { return }
      owner?.emit([
        "type": "progress",
        "pageId": id,
        "progress": progress,
      ])
    }
    urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, change in
      guard let self, let url = change.newValue as? URL else { return }
      owner?.emit([
        "type": "urlChanged",
        "pageId": id,
        "url": url.absoluteString,
      ])
    }
  }

  func attach() throws {
    guard !closed, let host = owner?.hostView else {
      throw BrowserMethodError("page_surface_unavailable", "The Flutter host view is unavailable.")
    }
    if webView.superview !== host {
      webView.removeFromSuperview()
      host.addSubview(webView, positioned: .above, relativeTo: nil)
    }
    attached = true
    updateSurfaceVisibility()
  }

  func detach() {
    attached = false
    webView.isHidden = true
    webView.removeFromSuperview()
  }

  func setBounds(x: Double, y: Double, width: Double, height: Double, scale: Double) throws {
    guard
      x.isFinite, y.isFinite, width.isFinite, height.isFinite, scale.isFinite,
      width >= 0, height >= 0, scale > 0
    else {
      throw BrowserMethodError("invalid_bounds", "Browser surface bounds are invalid.")
    }
    guard let host = owner?.hostView else {
      throw BrowserMethodError("page_surface_unavailable", "The Flutter host view is unavailable.")
    }
    let nativeY = host.isFlipped ? y : Double(host.bounds.height) - y - height
    surfaceBounds = NSRect(x: x, y: nativeY, width: width, height: height)
    webView.frame = surfaceBounds
    updateSurfaceVisibility()
  }

  func updateSurfaceVisibility() {
    let visible = attached && !obscured && surfaceBounds.width > 0 && surfaceBounds.height > 0
    webView.isHidden = !visible
    if visible {
      webView.superview?.addSubview(webView, positioned: .above, relativeTo: nil)
    }
  }

  func close() {
    guard !closed else { return }
    closed = true
    pendingUploadResult?(
      BrowserMethodError("page_closed", "The browser page was closed.").asFlutterError
    )
    pendingUploadResult = nil
    pendingUploadURLs = nil
    progressObservation = nil
    urlObservation = nil
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: Self.consoleHandlerName
    )
    webView.removeFromSuperview()
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard
      message.name == Self.consoleHandlerName,
      let value = message.body as? [String: Any],
      let level = value["level"] as? String,
      let rawMessage = value["message"] as? String
    else {
      return
    }
    owner?.emit([
      "type": "console",
      "pageId": id,
      "level": level,
      "message": String(rawMessage.prefix(65_536)),
    ])
  }

  private static let consoleBridgeScript = """
    (() => {
      if (window.__aleraConsoleBridgeInstalled) return;
      window.__aleraConsoleBridgeInstalled = true;
      for (const level of ['debug', 'info', 'warn', 'error', 'log']) {
        const original = console[level];
        console[level] = function(...values) {
          try {
            const message = values.map((value) => {
              if (typeof value === 'string') return value;
              try { return JSON.stringify(value); } catch (_) { return String(value); }
            }).join(' ');
            window.webkit.messageHandlers.aleraBrowserConsole.postMessage({
              level: level === 'warn' ? 'warning' : (level === 'log' ? 'info' : level),
              message,
            });
          } catch (_) {}
          return original.apply(console, values);
        };
      }
    })();
    """
}
