# Browser Tabs

Alera browser tabs use only the operating system browser engine: WKWebView on macOS, WebView2 on Windows, and WebKitGTK 4.1 on Linux. The app does not bundle Chromium or CEF.

## Stable Capability Gate

The feature is fail-closed. A platform must pass the complete capability probe before Alera enables browser tab creation or automation. The gate covers a native page surface, isolated persistent and ephemeral profiles, deterministic close, navigation events, JavaScript, full cookie attributes, deferred permission, TLS, popup and download decisions, DOM snapshots and actions, viewport and full-page screenshots, PDF export, Flutter overlay occlusion, atomic cookie import, manual JSON import, and every native import source required for that operating system.

There is no partial browser mode. A missing engine, Linux runner without `GtkOverlay`, incomplete cookie API, or unsupported import source keeps the feature unavailable and exposes the probe reason for diagnostics.

Current stable availability is:

| Platform | Stable Status | Reason |
| --- | --- | --- |
| macOS 14+ | Available When The Full Probe Passes | WKWebView delivers authentication challenges to the navigation delegate for the specific web view. |
| Windows | Hidden | WebView2's allow action is cached for the request host and certificate in the shared session, so the current backend cannot constrain an exception to one tab. |
| Linux | Hidden | WebKitGTK grants a certificate exception on `WebKitWebContext` for further errors on the host, so the current profile-shared context cannot constrain it to one tab. |

The Windows and Linux backends deliberately report `tlsCallbacks: false`; every other capability may exist, but stable browser tabs remain unavailable until the exact per-tab TLS contract can be met. This follows the native API semantics documented by [Microsoft WebView2](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2_14) and [WebKitGTK](https://webkitgtk.org/reference/webkit2gtk/stable/method.WebContext.allow_tls_certificate_for_host.html). The macOS implementation uses the per-web-view [WKNavigationDelegate authentication challenge](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webview%28_%3Adidreceive%3Acompletionhandler%3A%29).

## Ownership

Each persisted `WorkspaceTabRecord` with `kind == browser` owns one native browser page. Its tab id is also its page id. The payload stores the profile id plus only a URL and runtime title that pass the browser persistence filter. Page-controlled titles are stripped of control characters, trimmed, and capped at 1024 UTF-8 bytes. Titles are not persisted without a safe associated URL, and authentication or token-bearing URLs suppress them. Manual tab titles keep precedence over document titles.

`BrowserSessionRegistry` owns live page creation, visibility leases, command leases, overlay occlusion, and deterministic close. A native page may be detached from the Flutter surface while automation or capture keeps a lifecycle lease. Closing waits for active leases, closes the native page exactly once, and removes the session.

All persisted browser tabs, including background tabs, are rehydrated when the workspace snapshot changes. Reconciliation is generation-scoped so an older snapshot cannot close pages created by the latest snapshot. Changing profiles persists the new identity before replacing the native page. Native surfaces are obscured with a reference-counted lease while any Flutter modal is above them.

The Rust runtime owns profile metadata, history, recently closed tabs, remembered site permissions, and search settings in `runtime.sqlite`. History is written only after a completed navigation and is bounded to 200 deduplicated entries per profile. Recently closed tabs are bounded to the 10 most recent entries globally; the optional profile selector filters that retained set only when reading it. Sensitive authentication callback URLs, credentials, tokens, local files, `data:`, and `javascript:` URLs are never persisted.

## Browser Driver

The Flutter app registers a local browser driver with the runtime host and synchronizes its live pages. CLI requests such as `browser.navigate`, `browser.snapshot`, `browser.ref.click`, `browser.wait`, `browser.screenshot`, and `browser.pdf` are routed to the app connection that owns the page.

The runtime host refuses CLI `browser.open` and `browser.reopen` requests unless a connected app driver advertises the complete stable gate. Persisted records cannot be used to bypass a platform or startup-time capability failure.

The host serializes calls per page, bounds the per-page and global queues, assigns a deadline, and sends `browserDriverRequest` events to the app. The app completes each correlation through `browser.driver.complete`. Timeouts, cancellation, driver replacement, page close, and document generation changes cancel stale work. DOM references are scoped by page, snapshot, namespace, and document generation, and their live signature is revalidated before an action.

Screenshots and PDFs are written directly to private temporary paths by the native backend with exclusive-create semantics. Only artifact metadata crosses the Dart and runtime protocols. Each file is capped at 64 MiB, the store is capped at 256 MiB, and artifacts expire after 24 hours. Cookie-list automation strips values before returning results to a CLI caller.

Native calls that cannot be interrupted are quarantined after timeout or cancellation: the page accepts no other ordinary UI or driver command and cannot close until that native future drains. A callback decision overlay caused by the active native operation remains allowed so it can deny or resolve the pending callback. The timed-out caller must treat a mutation's outcome as unknown because the platform operation may already have taken effect. A cancelled capture deletes any artifact that appears after the host removed its reservation.

`browser.eval` is an explicit privileged capability available only to a local authenticated caller. It can read data available to page JavaScript, including DOM values, `document.cookie`, and web storage. Snapshot redaction and cookie-list value stripping reduce accidental disclosure; they are not a security boundary against an explicit eval command.

## Profiles And Import

The default profile cannot be deleted. Other profiles use physically isolated browser-engine storage. Profile deletion is refused while a browser tab still references that profile.

CLI profile inspection is read-only. Profile creation, deletion, and cookie import stay in the app so the runtime catalog and native storage partition are coordinated as one operation.

Cookie import starts only from an explicit, fresh, one-use UI gesture. Import probes and decrypts into an isolated profile, validates the complete batch, and commits atomically. A failed or cancelled import leaves the target profile unchanged. Source metadata records the browser family, source profile name when available, and import time without storing external credentials.

Required sources are:

| Platform | Sources |
| --- | --- |
| macOS | Chrome, Edge, Arc, Brave, Comet, Helium, Firefox, Safari, Manual JSON |
| Windows | Chrome, Edge, Brave, Comet, Firefox, Manual JSON |
| Linux | Chrome, Edge, Brave, Firefox, Manual JSON |

## Security Decisions

Permission, TLS, popup, and download callbacks deny by default and have bounded deadlines. Screen capture requested by a page is always denied. Remembered permissions are profile and origin scoped.

Public certificate failures cannot be bypassed. A native backend may offer a temporary exception only for the exact local origin and current tab named by the challenge. Eligible origins are HTTPS loopback, private IPv4, IPv4 or IPv6 link-local addresses, and `.local` or `.localhost` hosts. The exception applies only to the challenged host and port for that page lifetime. Popups require a trusted user gesture; allowed popups receive a new transient page with opener semantics preserved. Downloads require an explicit destination and report progress without blocking the Flutter main isolate.

The address policy accepts `http`, `https`, and internal `about:blank`. A hostname without a scheme uses HTTPS, except loopback addresses which use HTTP. Other input becomes a query for the selected search engine. File paths and all other schemes are rejected before reaching the native engine.

## Platform Packaging

macOS browser tabs require macOS 14 or newer. Windows uses the installed evergreen WebView2 runtime. Linux CI installs `libwebkit2gtk-4.1-dev`; Debian packages depend on `libwebkit2gtk-4.1-0`, and RPM packages require `webkit2gtk4.1`. The Linux runner places the Flutter view inside a `GtkOverlay` so the browser plugin can position and explicitly obscure its native child surface.
