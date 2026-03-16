# Platform Compatibility Analysis — Alera

**Date:** 2026-03-16
**Branch:** analyze-platform-compat

## Context

Analysis of project dependencies to determine on which platforms Alera could currently run, and evaluation of migrating `pasteboard` to `super_clipboard` for Web support.

## Pasteboard vs Super Clipboard

### pasteboard (current dependency)

- **Latest version:** 0.5.0
- **Platforms:** macOS, Windows, Linux, Android, iOS (no Web)
- **Usage in project:** only `Pasteboard.image` to read image bytes from clipboard
- **Used in:**
  - `lib/src/features/session/presentation/widgets/composer.dart:428`
  - `lib/src/features/session/presentation/widgets/queue_message_edit_dialog.dart:214`

### super_clipboard 0.9.1

- **Platforms:** macOS, Windows, Linux, Android, iOS, **Web**
- **Heavy dependency chain:** `super_native_extensions` + `irondash_engine_context` + `irondash_message_channel` + `device_info_plus` + `ffi`
- **Does support Web** via `flutter_web_plugins` and `SuperNativeExtensionsWeb` class

### Migration effort

- **Mechanically simple:** only 2 files, 1 call each
- **Code change:**
  ```dart
  // Before
  final bytes = await Pasteboard.image;

  // After
  final clipboard = SystemClipboard.instance;
  final reader = clipboard.reader;
  final image = reader.readImage();
  final bytes = image?.bytes;
  ```
- **Downside:** `super_clipboard` pulls in a heavy dependency chain (FFI, device_info_plus, etc.) just to read clipboard images

### Flutter Clipboard alternative

- `Clipboard.getData()` (from `flutter/services.dart`, already imported) supports Web but **does not support reading images** — text only
- Not viable as a replacement for the current use case

## Conclusion

- Migrating to `super_clipboard` is mechanically trivial (2 lines) but adds significant dependency weight
- If Web support is a near-term goal, the migration is worth it
- If Web is not needed soon, `pasteboard` remains the lighter option for the current use case
