import Cocoa
import FlutterMacOS
import Speech

@main
class AppDelegate: FlutterAppDelegate {
  private var desktopPresence: DesktopPresence?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // FlutterAppDelegate does not implement this optional Objective-C callback.
    // Calling super throws before the native channels can be registered.
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "dev.leynier.alera/speech_capabilities",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "supportsOnDevice" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let localeId = arguments?["localeId"] as? String
      let locale = localeId.map { Locale(identifier: $0) } ?? Locale.current
      result(SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true)
    }
    desktopPresence = DesktopPresence(messenger: controller.engine.binaryMessenger)
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      desktopPresence?.requestShow()
    }
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // AppKit can request termination when the last window is hidden too.
    // The Dart close/quit flow calls NSApp.terminate explicitly when needed.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
