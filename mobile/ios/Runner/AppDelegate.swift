import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AleraSpeechCapabilities"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "dev.leynier.alera/speech_capabilities",
      binaryMessenger: registrar.messenger()
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
  }
}
