# Flutter 3.47 Upgrade

## Scope

Desktop and mobile use Flutter 3.47.2 / Dart 3.13.2 while retaining Dart language 3.12 through their existing SDK lower bounds. The shared CI action pins the exact Flutter version. This migration does not change protocols, storage schemas, distribution, desktop/Android platform minimums, Rust/Zig toolchains, FRB 2.12.0, or terminal forks. iOS now requires 15.0, matching the SDK's mandatory deployment-target migration.

## Compatibility Decisions

- Preserve Skia on Linux using Flutter's supported embedder API. Five samples with the new Impeller default increased median terminal CPU from 47.1% to 84.2% of one core for line output and from 53.0% to 91.3% for full-screen output; raster time increased from 4.67 to 15.77 ms and from 5.71 to 16.92 ms respectively. Other platforms retain their defaults. Validate performance and real text separately from goldens, which obscure text.
- Preserve resource fingerprint timestamps at millisecond precision, serialized as microseconds. Tests use hashes captured with Dart 3.12.2 and verify legacy markers, changed sources, and unmanaged resources.
- Adapt `AleraPreview` to the new abstract `PreviewThemeData.apply` API while retaining the dark theme and Inter typography.
- Preserve the terminal overrides in each generated preview scaffold. Separate quota presentation from native reset/TUI actions because the new preview detector includes these previews in its web compilation; the existing application widget retains both actions and its constructor interface.
- Give mobile previews a bounded phone viewport and use a Material surface in both preview wrappers so Flutter's ListTile ink validation does not reject an intervening opaque ColoredBox. Both mobile previews render, with layout regression tests. A transient SDK analysis-server concurrent-modification error was observed during hot reload; a fresh launch with the default detector successfully renders the galleries. The hidden legacy detector is not a workaround because its scaffold does not establish the required DTD connection.
- Move the existing Riverpod lint plugin to the supported top-level analyzer plugin configuration, pinned to the existing 3.1.4 version. Do not suppress its warnings.
- Await asynchronous work inside `try` blocks so errors reach the intended handlers and temporary files remain available until readers finish.
- Retain Android AGP 8.13.2, Gradle 8.14.3, Kotlin 2.3.20, Java 17, and CocoaPods. Mobile explicitly opts out of the new default SwiftPM migration. The first iOS CI build demonstrated that Flutter raises the deployment target from 13.0 to 15.0, so the checked-in project and Podfile now agree with that requirement.
- Resolve from existing lockfiles. Only `matcher`, `meta`, `test`, `test_api`, `test_core`, and `vector_math` changed to satisfy the new SDK. Generator versions and inputs did not change, so generated bindings were not regenerated.
- Keep analyzer exclusions for submodules, native scaffolding, and mobile; retain Flutter's added exclusions for build output and native platform directories.

## Validation Record

Baseline: Flutter 3.44.8 / Dart 3.12.2 in an isolated Puro environment, without changing the global SDK. Desktop analysis and 3,374 tests passed (one skipped); mobile analysis and 598 tests passed. Baseline terminal restoration completed all five measured replays within the existing three-second target, with a 2,043.98 ms median.

Flutter 3.47.2: desktop analysis passes with the modern Riverpod plugin. Desktop has 3,381 passing tests (one skipped), including the four reviewed goldens rechecked separately. Mobile analysis and 599 tests pass. The local browser package passes analysis and all 22 tests. The file-length ratchet passes without increasing its baseline. Seven native Linux tests pass; the smoke fixture now returns its initialized database synchronously, matching the production bootstrap rather than exposing `AsyncLoading` during mount.

Seven golden changes were inspected before regeneration: four desktop snapshots (375, 570, 808, and 2,997 differing pixels) and three mobile snapshots (38, 228, and 228 differing pixels). Differences affect border rasterization, with no content or layout displacement. Separate native Linux captures verify Inter, JetBrains Mono, Unicode, terminal colors, and text scales 1x, 1.5x, and 2x.

The Android release APK builds locally with the existing debug-key fallback. Native dependencies are verified for armeabi-v7a, arm64-v8a, and x86_64, including the required bundled C++ runtime. AGP/Gradle deprecation warnings remain visible; neither version nor validation is bypassed.

Final build, test, and performance results are recorded against the exact commit in [PR #585](https://github.com/leynier/alera/pull/585). The PR remains in draft to prevent automatic merge; this task does not authorize merging or publication.

During validation, `main` incorporated xterm2 and relay changes. These were merged without replacing their pinned dependencies; an additional awaited return restores Dart 3.13 compatibility in relay identity migration. After integration, desktop analysis and 3,392 tests pass (one skipped), mobile analysis and 619 tests pass (three explicit integration-only skips). Ten xterm2 input/selection/clipboard tests and 18 quota behavior tests pass. The desktop previewer now compiles all 89 previews with its default detector and renders the quota views without browser console errors. Performance comparisons are being repeated with xterm2 rather than attributing the concurrent terminal migration to the SDK.

The subsequent integration of `main` at `3cf74356` preserves configuration sync, macOS startup/tray fixes, and the Windows single-instance runner. Desktop, mobile, and the new configuration package pass analysis; all 13 configuration-package tests pass. Desktop CI now also exercises the existing native macOS presence test and Windows runner tests. The iOS workflow retains its resolved CocoaPods lockfile for dependency review.

After that integration, all four desktop test shards and coverage pass, the complete mobile suite passes 629 tests with the same three skips, all four desktop goldens pass, and 33 xterm2 tests cover rendering, IME composition placement, input, selection, and clipboard behavior. Native Linux checks pass for typography at three scales, browser/PDF/video orientation, tray activation/menu/badge, workbench tab creation, and six Rust process-runner scenarios. Native fixtures use temporary files, ephemeral browser profiles, and the test process's own tray identity, never real terminal sessions.

The updated preview scaffolds compile 90 desktop and three mobile previews. The new mobile configuration preview renders correctly. The desktop gallery rendered before the last main integration; the native typography captures separately verify its fonts and colors. The SDK previewer exhibited intermittent analysis-server and native-hook cache errors; a scaffold clean followed by restoring the tracked overrides produces a successful compilation. Browser connection failures during the final desktop gallery check are recorded as a tooling limitation, not a successful visual review of that last gallery revision. CI exports native typography captures from all three desktop platforms for review of real fonts, scales, and renderer output. These captures do not measure a physical display's wide-gamut calibration. Dictation regression tests use injected providers and do not record a real microphone or contact a production transcription account.

The checked-in iOS CocoaPods lockfile now matches the successful native build, including the already-declared mobile plugins that were absent from the old lockfile. CI verifies that device and simulator builds do not change it. No Dart dependency was upgraded for this lockfile refresh.

## Reproduction

Run the format, analysis, test, and native build commands documented in [Testing](testing.md). `Mobile Builds` adds Android release builds with the existing debug-signing fallback, native-library verification, unsigned iOS release builds, and iOS simulator builds. `Desktop Builds` remains the existing three-platform release build workflow. Neither workflow distributes an app.

Run the terminal render and flush-cadence benchmarks five times per SDK on the same machine, and run the restore benchmark, which contains five measured replays. Use the commands and measurement boundaries in [Performance](performance.md). Investigate reproducible median CPU or latency regressions above 10%; do not relax the restore target.

## Sources

- [Flutter 3.47 release notes](https://flutter.dev/blog/whats-new-in-flutter-3-47)
- [Flutter breaking changes](https://docs.flutter.dev/release/breaking-changes)
- [Flutter 3.47.2 release](https://github.com/flutter/flutter/releases/tag/3.47.2)
- [Dart changelog](https://dart.dev/changelog)
- [Analyzer plugins](https://dart.dev/tools/analyzer-plugins)
- [PreviewThemeData API](https://api.flutter.dev/flutter/widget_previews/PreviewThemeData-class.html)
- [Impeller availability and Linux opt-out](https://docs.flutter.dev/perf/impeller)
