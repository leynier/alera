# Rebuilding Orca in Flutter and Dart: Technical Feasibility & Research Report

This report evaluates the feasibility of migrating Orca (an AI Orchestrator for parallel development) from Electron, Node.js, and React to a unified **Flutter (Dart)** application. It provides an architectural mapping, feature-by-feature implementation analysis, package research (stability and maintenance), and highlights the easy vs. complicated parts of the migration.

Current Alera note: this is historical research and a source of implementation
ideas, not the current dependency contract. The active app is intentionally
terminal-first and currently ships the project registry, Git-worktree-backed
workspaces, split terminal workbench, and local Sembast persistence. Features
listed below such as Markdown previews, Drift, browser automation, SSH, tray
menus, and notifications are research candidates until they are explicitly
added to the active app.

---

## 1. Architectural Stack Mapping

| Component | Current Electron Stack | Proposed Flutter / Dart Stack | Feasibility & Stability |
| :--- | :--- | :--- | :--- |
| **App Runtime** | Electron (Node.js + Chromium) | Flutter Desktop (Dart VM + Flutter Engine) | **Very High**: Unified codebase, native UI rendering. |
| **Pseudoterminal (PTY)** | `node-pty` (Native C++ Bindings) | `portable_pty` / `portable_pty_flutter` (C/C++ via `dart:ffi`) | **High**: Excellent, modern cross-platform library. |
| **Terminal UI Renderer** | `@xterm/xterm` (HTML Canvas / WebGL) | `ghostty_vte_flutter` (FFI bindings to Ghostty's Zig engine) | **Very High**: High performance, native GPU acceleration. |
| **Git Operations** | `simple-git` (Node CLI wrapper) | `Process.run('git', ...)` via `dart:io` | **Very High**: Simple, uses user's native git shell environment. |
| **Persistence Database** | `better-sqlite3` | `sqlite3` via FFI + `drift` (reactive ORM) | **Very High**: Industry standard, type-safe, reactive updates. |
| **File System Watcher** | `@parcel/watcher` | `Directory.watch` (`dart:io`) or `watcher` package | **High**: Native watch can fall back to polling, stable for worktrees. |
| **Embedded Browser** | Electron `<webview>` + CDP | `flutter_inappwebview` + Headless Chrome (for CDP automation) | **Medium-Hard**: Platform differences (WebKit vs Chromium). |
| **SSH Client** | `ssh2` (Native Node module) | `dartssh2` (Pure Dart SSH client) | **Very High**: Robust, maintained, handles SSH & SFTP. |
| **Speech (STT / TTS)** | `sherpa-onnx` (Native wrapper) | `sherpa_onnx` (Official Dart/Flutter wrapper) | **High**: Core engine already compiled; package is well-maintained. |
| **Drag & Drop Files** | React HTML5 Drag & Drop APIs | `desktop_drop` (Platform view drop listeners) | **Very High**: Excellent stability, native UI drop hooks. |
| **Tray & Menu Icon** | Electron Tray & Menu APIs | `tray_manager` + `system_tray` (System menus) | **Very High**: Maintained, native menus on Mac, Win, Linux. |
| **Notifications** | Electron Notification API | `local_notifier` (Native desktop notifications) | **Very High**: Clean API, supports click callbacks. |
| **Markdown Previews** | `react-markdown` + `rehype`/`remark` | `flutter_markdown` (Markdown widgets) | **Very High**: Extremely stable, native rendering. |
| **PDF Previews** | `pdfjs-dist` (HTML Canvas) | `pdfx` (Native PDF rendering) | **Very High**: Uses PDFium/PDFKit, much faster than PDF.js. |
| **Diagram Rendering** | `mermaid.js` (JavaScript Web Engine) | Local HTML Mermaid + `InAppWebView` | **High**: Simple to isolate inside a headless iframe. |
| **CLI Scripting** | Node CLI executable (`bin/orca`) | Compiled native Dart binary (`dart compile exe`) | **Very High**: No node runtime required, instantaneous startup. |

---

## 2. Package Feasibility & Recommendation Table

We researched `pub.dev` and GitHub to identify maintained, production-ready packages for each feature, discarding unmaintained or obsolete options.

| Package Name | Publisher / Repository | Latest Version | Maintenance / Health | Role & Selection Rationale |
| :--- | :--- | :--- | :--- | :--- |
| [**`portable_pty`**](https://pub.dev/packages/portable_pty) | `kingwill101` / `dart_terminal` | `0.0.5` | **Active**: Part of the new `dart_terminal` monorepo, updated May 2026. | Spawns shell processes inside pseudo-terminals on macOS, Windows, Linux, and Android. Decoupled from rendering logic. |
| [**`ghostty_vte_flutter`**](https://pub.dev/packages/ghostty_vte_flutter) | `kingwill101` / `dart_terminal` | `0.1.3` | **Active**: Active development, 0 open issues, updated May 2026. | Renders the terminal UI using FFI bindings to `libghostty-vt` (Ghostty's virtual terminal engine). Premium alternative to WebGL xterm. |
| [**`drift`**](https://pub.dev/packages/drift) | `simolus3` (Google Developer Expert) | `2.x.x` | **Extremely Active**: Industry standard, 100% test coverage. | Reactive, type-safe persistence layer. Replaces Prisma/better-sqlite3. Supports automatic schema migrations and live queries. |
| [**`dartssh2`**](https://pub.dev/packages/dartssh2) | `terminal.studio` / `dartssh2` | `2.x.x` | **Highly Active**: Popular SSH library in the Dart ecosystem. | Replaces the Node `ssh2` library. Supports SSH tunnels, shell sessions, and SFTP file listings for remote worktrees. |
| [**`flutter_inappwebview`**](https://pub.dev/packages/flutter_inappwebview) | `inappwebview.dev` / `pichillilorenzo` | `6.1.5` | **Extremely Active**: Multi-platform webview plugin with gold-standard support. | Provides inline webview, cookie injection, session storage, and custom JS injection for the embedded browser and "Design Mode". |
| [**`tray_manager`**](https://pub.dev/packages/tray_manager) | `leanflutter.dev` | `0.5.2` | **Active**: Over 110k downloads, solid maintenance. | Controls system tray icons, context menus, and click/double-click interactions across Windows, macOS, and Linux. |
| [**`local_notifier`**](https://pub.dev/packages/local_notifier) | `leanflutter.dev` | `0.1.6` | **Active**: Active desktop notifier. | Displays native desktop notifications (banners/alerts) with action buttons and click events. |
| [**`pdfx`**](https://pub.dev/packages/pdfx) | `creativecreatorormaybenot` | `2.6.0` | **Active**: Leading PDF renderer in Flutter. | Renders PDF files natively on desktop platforms (PDFium on Windows/Linux, PDFKit on macOS). |
| [**`github`**](https://pub.dev/packages/github) | `spinlock.sh` | `9.25.1` | **Active**: Well-maintained GitHub API Client. | Replaces JavaScript Octokit for PR reviews, issue management, and GitHub actions integrations. |
| [**`graphql`**](https://pub.dev/packages/graphql) | `zino.company` | `5.2.4` | **Active**: Core GraphQL client. | Used for Linear API integrations (issues, workflow automation). |
| [**`desktop_drop`**](https://pub.dev/packages/desktop_drop) | `mixin.dev` | `0.7.1` | **Highly Active**: Over 400k downloads, very stable on desktop. | Allows dragging files and folders from the OS file manager directly into prompt input bars or terminal zones. |
| [**`sherpa_onnx`**](https://pub.dev/packages/sherpa_onnx) | `k2-fsa` / Next-gen Kaldi | `1.12.37` | **Highly Active**: Frequent releases, official Dart support. | Provides offline local ASR (speech-to-text) and TTS (text-to-speech) capabilities on macOS, Windows, Linux, Android, iOS. |
| [**`multi_split_view`**](https://pub.dev/packages/multi_split_view) | `caduandrade.net` | `3.6.1` | **Active**: 160 pub points, widely used. | Handles horizontal/vertical resizable panel layouts, vital for splitting terminals, file managers, and code editors. |

> [!CAUTION]
> **Discarded Package: `pty` and `flutter_pty` (TerminalStudio)**
> The original `pty` and `flutter_pty` packages on pub.dev (which were popular in 2022-2024) are now largely unmaintained and suffer from socket pipe leaks and issues on Windows ConPTY. Instead, use **`portable_pty`** and **`ghostty_vte_flutter`** by `kingwill101`, which use modern `dart:ffi` bindings and are actively maintained as of 2026.

---

## 3. The Easy Parts (Quick Implementation)

These features map directly to native Dart or Flutter capabilities and do not require heavy shims or native workarounds:

1. **Git Worktree Orchestration**
   * *Mechanism*: Releasing, creating, and cleaning up worktrees is done by executing the user's system `git` CLI.
   * *Implementation*: We use Dart's `Process.run('git', ['worktree', 'add', ...])` from `dart:io`. Dart handles async subprocess execution natively and safely.
2. **SSH Connection & Remote Management**
   * *Mechanism*: The `dartssh2` package provides a pure Dart implementation of SSH-2 and SFTP. It does not require compiling native C libraries.
   * *Implementation*: Managing SSH connections, tunnels, file reads/writes, and executing remote agents is fully supported by `dartssh2`.
3. **Task & API Integration (GitHub, Linear)**
   * *Mechanism*: Integrations communicate using standard JSON/HTTPS REST or GraphQL APIs.
   * *Implementation*: Using `package:http` or `package:dio` along with `package:github` and `package:graphql` is fast and doesn't require any platform-specific code.
4. **Local Database & State Persistence**
   * *Mechanism*: Orca needs a local SQLite DB for configuration, terminal history, usage tracking, and workspaces.
   * *Implementation*: `drift` (combined with FFI `sqlite3`) compiles smoothly across macOS, Windows, Linux, iOS, and Android. It also provides reactive streams so the UI updates automatically when DB rows change. For encrypting agent keys or tokens, use `flutter_secure_storage`.
5. **System Notifications & System Tray Menus**
   * *Mechanism*: Native system notification banners and minibar tray status indicators.
   * *Implementation*: `local_notifier` and `tray_manager` expose clean APIs that map directly to macOS Apple Notifications, Windows Toast Notifications, and Linux DBus notifications.
6. **Rich Markdown & PDF Previews**
   * *Mechanism*: File previews of Markdown files and PDF reports inside workspaces.
   * *Implementation*: Markdown is parsed natively using `flutter_markdown`. PDF rendering via `pdfx` uses PDFium (Windows/Linux) and PDFKit (macOS), which is natively faster, smoother, and consumes less memory than Electron's PDF.js wrapper.
7. **CLI Utility (`orca` binary)**
   * *Mechanism*: Electron projects require heavy wrappers or node executables to script CLI operations.
   * *Implementation*: Dart lets us write a CLI script (using `package:args`) and compile it directly into a single, dependency-free native executable via `dart compile exe`. It boots in milliseconds and can communicate with the main Flutter GUI over standard TCP sockets or Unix Sockets.

---

## 4. The Complicated Parts (Architectural Gaps)

Some features are difficult to implement in Flutter due to platform sandbox limits, operating system differences, or the lack of a shared web engine (like Electron's Chromium).

### A. Chrome DevTools Protocol (CDP) & Browser Automation Mismatch
*   **The Issue**: Orca uses Electron's native debugger tools to expose a CDP socket proxy (`cdp-ws-proxy.ts` and `cdp-bridge.ts`). This allows CLI agents (like Anthropic Claude computer use) to connect to the embedded browser and click/inspect elements or take screenshots.
*   **Why it's hard in Flutter**: 
    *   Flutter's WebViews are platform-native wrappers: **WKWebView** on macOS, **WebView2** (Edge/Chromium) on Windows, and **WebKitGTK** (or WPE WebKit) on Linux.
    *   While WebView2 (Windows) supports CDP events natively, WKWebView (macOS) and WebKit2GTK (Linux) do **not** support CDP WebSocket connections. Translating CDP to Apple's private Remote Inspector APIs is fragile and not feasible for production.
*   **The Solution**:
    1.  **Headless Subprocess**: Instead of running the agent browser inside the main WebView, launch an external Chrome/Chromium process in the background with `--remote-debugging-port=xxxx`.
    2.  **Screencast Bridge**: Connect to this headless Chrome via WebSockets in Dart, capture screenshots via CDP (`Page.captureScreenshot`), and stream them to a CustomPaint widget in Flutter. Mouse and keyboard interactions in Flutter are captured and forwarded back to Chrome using CDP's `Input.dispatchMouseEvent` and `Input.dispatchKeyEvent`.
    3.  This is highly cross-platform, preserves full CDP compatibility for all CLI agents, and works on all OSs without native WebView engine differences.

### B. High-Performance Text Editor (Monaco Editor Integration)
*   **The Issue**: Orca uses VS Code's `monaco-editor` inside React for source control diff viewing, annotations, and quick file editing.
*   **Why it's hard in Flutter**:
    *   There is no native Flutter text editor that matches Monaco's capabilities (LSP integration, multi-cursor, code folding, minimap, diff comparisons).
    *   Native code editors like `code_text_field` are basic syntax highlighters and are not suitable for full-scale workspace editing.
*   **The Solution**:
    *   Embed a local instance of Monaco Editor inside an `InAppWebView` widget.
    *   Communicate edits, styling tokens, and diff payloads back to Flutter via Javascript channels (`InAppWebViewController.addJavaScriptHandler`). This provides a VS Code class editing experience on desktop while remaining decoupled.

### C. Global Workspace Search (ripgrep & FTS5)
*   **The Issue**: Users need to perform extremely fast keyword searches across their entire repository and terminal history.
*   **Why it's hard in Flutter**:
    *   Scanning massive workspace folder structures recursively using pure Dart file streams is too slow for large repositories.
*   **The Solution**:
    1.  **File Search**: Pre-compile a standalone `ripgrep` (`rg`) binary for macOS, Windows, and Linux, and bundle it as a native asset. Spawn `ripgrep` as a subprocess via Dart's `Process` APIs, parsing the JSON output stream to render fast file matches. This is identical to the mechanism used by VS Code and the current Orca architecture.
    2.  **Terminal Log Search**: For searching terminal history logs, configure SQLite's **FTS5 (Full Text Search)** extension via `drift` to maintain a search index of past sessions, allowing sub-millisecond keyword matches.

### D. Diff Annotation (AI Code Annotations)
*   **The Issue**: Annotating specific lines in a Git diff before committing (associated with AI generated changes).
*   **Why it's hard in Flutter**:
    *   Drawing custom overlays, comment boxes, and line decorations inside a native list of code lines requires tracking lines and spacing carefully.
*   **The Solution**:
    1.  If using the **Monaco Webview Editor**, use Monaco's native decoration APIs (`editor.deltaDecorations`) and zone overlays (`editor.addViewZone`) by executing custom Javascript from Dart to inject annotations inline.
    2.  If using a **Native Flutter Diff Renderer**, build a custom layout where each diff line is a widget inside a list, and inject collapsible annotation inputs/cards between list items depending on the line coordinates stored in SQLite.

---

## 5. Conclusion & Feasibility Summary

### Is it feasible?
**Yes, 100% feasible.** Rebuilding Orca in Flutter and Dart is highly practical and would result in:
1.  **Drastic RAM & Size Reductions**: Replaces Electron (approx. 150MB+ footprint and 200MB+ idle RAM) with a native Flutter desktop app (approx. 20-30MB executable and under 80MB RAM).
2.  **Unification of Mobile Companion**: The React Native Expo companion app can be merged into a single Flutter monorepo, allowing model wrappers, state managers (Zustand -> Bloc/Riverpod), and database interfaces to be shared across iOS, Android, and Desktop.
3.  **Zig/Ghostty Terminal Engine**: Using `ghostty_vte_flutter` gives Orca a hardware-accelerated terminal experience that matches Ghostty's high-speed rendering.

### Migration Roadmap Suggestion
1.  **Phase 1: Shell & Terminal**: Setup `portable_pty` and `ghostty_vte_flutter` inside a `multi_split_view` layout to establish the core workspace terminal layout.
2.  **Phase 2: Git Worktree & persistence**: Implement Git CLI process wrappers and setup `drift` for workspace configuration caching.
3.  **Phase 3: Integrations & Editor**: Add SSH client connection capabilities (`dartssh2`), REST/GraphQL calls for GitHub and Linear, and integrate the Monaco WebView editor.
4.  **Phase 4: Browser Automation**: Implement the external Headless Chromium browser bridge to maintain 100% compatibility with Claude's computer use features.
