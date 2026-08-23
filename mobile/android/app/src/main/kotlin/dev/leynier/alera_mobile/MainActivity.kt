package dev.leynier.alera_mobile

import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.leynier.alera/speech_capabilities",
        ).setMethodCallHandler { call, result ->
            if (call.method != "supportsOnDevice") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(this),
            )
        }
        ExternalBrowserLauncher.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )
    }
}
