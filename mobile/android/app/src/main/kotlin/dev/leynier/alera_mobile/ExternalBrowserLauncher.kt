package dev.leynier.alera_mobile

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Opens http(s) URLs in the device's standalone browser.
 *
 * `url_launcher`'s ACTION_VIEW stays in Alera's task and can resolve to Chrome
 * Custom Tabs or a host-specific app (GitHub's in-app browser for APK links).
 * The selector matches generic browsers only, and NEW_TASK puts that browser
 * in its own recents entry.
 */
internal object ExternalBrowserLauncher {
    const val CHANNEL = "dev.leynier.alera/external_browser"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrBlank()) {
                result.error("invalid_url", "A URL is required.", null)
                return@setMethodCallHandler
            }
            result.success(open(activity, url))
        }
    }

    fun open(activity: Activity, url: String): Boolean {
        val uri = Uri.parse(url)
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") {
            return false
        }
        if (start(activity, browserViewIntent(uri))) {
            return true
        }
        val selectorIntent =
            Intent.makeMainSelectorActivity(
                Intent.ACTION_MAIN,
                Intent.CATEGORY_APP_BROWSER,
            ).apply {
                data = uri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        return start(activity, selectorIntent)
    }

    private fun browserViewIntent(uri: Uri): Intent {
        return Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // Match handlers of generic https URLs (browsers), not github.com
            // apps that swallow the link into an in-app WebView.
            selector =
                Intent(Intent.ACTION_VIEW).apply {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                    data = Uri.parse("https:")
                }
        }
    }

    private fun start(activity: Activity, intent: Intent): Boolean {
        return try {
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
