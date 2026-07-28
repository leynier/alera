# Alera Browser

`alera_browser` is Alera's desktop browser boundary. It exposes one Dart API over WKWebView on macOS, WebView2 on Windows, and WebKitGTK 4.1 on Linux.

The package registers exactly one native backend per platform. It does not bundle Chromium, CEF, or a partial secondary web-view adapter.

Every optional operation is guarded by an explicit runtime capability. Unsupported or unsafe operations throw `AleraBrowserUnsupportedError`; they never silently fall back to a weaker behavior.
