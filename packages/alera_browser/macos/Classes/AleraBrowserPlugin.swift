import Cocoa
import FlutterMacOS
import WebKit

public final class AleraBrowserPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let methodChannelName = "dev.leynier.alera/browser"
  static let eventChannelName = "dev.leynier.alera/browser/events"
  static let requiredImportSources = [
    "chrome", "edge", "arc", "brave", "comet", "helium", "firefox", "safari",
  ]

  weak var hostView: NSView?
  var eventSink: FlutterEventSink?
  var profiles: [String: BrowserProfile] = [:]
  var pages: [String: BrowserPage] = [:]
  var decisions: [String: PendingBrowserDecision] = [:]
  var downloads: [ObjectIdentifier: BrowserDownload] = [:]
  var activeCookieImports: Set<String> = []
  let importQueue = DispatchQueue(
    label: "dev.leynier.alera.browser.cookie-import",
    qos: .userInitiated
  )

  init(hostView: NSView?) {
    self.hostView = hostView
    super.init()
    installStoredProfiles()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = AleraBrowserPlugin(hostView: registrar.view)
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(plugin, channel: methodChannel)
    eventChannel.setStreamHandler(plugin)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.handle(call, result: result)
      }
      return
    }
    do {
      switch call.method {
      case "probe":
        result(probeCapabilities())
      case let method where method.hasPrefix("profile."):
        try handleProfileMethod(method, arguments: call.browserArguments, result: result)
      case let method where method.hasPrefix("page."):
        try handlePageMethod(method, arguments: call.browserArguments, result: result)
      case let method where method.hasPrefix("cookies."):
        try handleCookieMethod(method, arguments: call.browserArguments, result: result)
      case let method where method.hasPrefix("capture."):
        try handleCaptureMethod(method, arguments: call.browserArguments, result: result)
      case let method where method.hasPrefix("cookieImport."):
        try handleCookieImportMethod(method, arguments: call.browserArguments, result: result)
      case "decision.resolve":
        try resolveDecision(arguments: call.browserArguments)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(error.asFlutterError)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func emit(_ event: [String: Any]) {
    if Thread.isMainThread {
      eventSink?(event)
    } else {
      DispatchQueue.main.async { [weak self] in self?.eventSink?(event) }
    }
  }

  private func probeCapabilities() -> [String: Any] {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let engineVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    let engineAvailable: Bool
    if #available(macOS 14.0, *) {
      engineAvailable = NSClassFromString("WKWebView") != nil
    } else {
      engineAvailable = false
    }
    let available = engineAvailable && hostView != nil
    var value: [String: Any] = [
      "engine": "wkWebView",
      "engineVersion": engineVersion,
      "engineAvailable": engineAvailable,
      "pageSurface": available,
      "isolatedProfiles": available,
      "ephemeralProfiles": available,
      "deterministicPageClose": available,
      "navigation": available,
      "navigationEvents": available,
      "javascript": available,
      "basicCookies": available,
      "fullCookies": available,
      "permissionCallbacks": available,
      "tlsCallbacks": available,
      "tlsTrustScope": available ? "page" : "none",
      "popupCallbacks": available,
      "downloadCallbacks": available,
      "domSnapshot": available,
      "domActions": available,
      "crossOriginFrameAutomation": false,
      "nativeFileUpload": available,
      "trustedInputEvents": false,
      "viewportScreenshot": available,
      "fullPageScreenshot": available,
      "pdf": available,
      "flutterOverlayOcclusion": available,
      "atomicCookieImport": available,
      "manualJsonCookieImport": available,
      "nativeCookieImportSources": available ? Self.requiredImportSources : [],
      "requiredNativeCookieImportSources": Self.requiredImportSources,
    ]
    var limitations = [
      "cross_origin_frames_unavailable",
      "trusted_input_events_unavailable",
    ]
    if !engineAvailable {
      limitations.append("macos_14_or_wkwebview_required")
    } else if hostView == nil {
      limitations.append("flutter_host_view_unavailable")
    }
    value["limitations"] = limitations
    return value
  }

  deinit {
    for decision in Array(decisions.values) {
      decision.cancelWithDefault()
    }
    for page in Array(pages.values) {
      page.close()
    }
  }
}
