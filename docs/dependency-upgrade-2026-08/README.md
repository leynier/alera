# Dependency upgrade - August 2026

Implementation of the approved dependency-upgrade goal. Registry versions were captured on 2026-08-30 at 19:25 UTC against baseline commit `030e4cb86c7db2bcb71bdac78fa0b0bb4b49738c`; the selected targets do not float during validation.

## Scope and compatibility

The upgrade covers the desktop app, mobile app, both shared Dart packages, both native plugin manifests, the standalone runtime packager, the Rust workspace and the independent Cloud workspace. Only stable versions are selected. Existing forks, submodule commits, copied Cargokit, media binaries, checksums, licenses, Rust editions, build profiles, OS minimums, wire formats, authentication requirements and persisted schemas remain unchanged.

There is no release, deployment, production credential change or merge in this work. Builds use isolated output directories and the remote SDKs are installed beside the build copies rather than replacing another project's SDK.

## Main changes

| Component | Before | Selected version |
| --- | --- | --- |
| Rust toolchain | 1.96 | 1.98.0 |
| Flutter / Dart | 3.47.2 / 3.13.2 | Unchanged, revalidated stable |
| Flutter Rust Bridge, Dart/Rust/generator | 2.12.0 | 2.13.0 |
| Desktop drop | 0.7.1 | 0.8.2 |
| Mobile secure storage | 10.3.1 | 11.0.0 |
| Notifications, desktop / mobile | 22.2.0 / 21.0.0 | 22.3.0 |
| Flutter Riverpod | 3.4.1 | 3.4.2 |
| Riverpod annotation / generator / lint | 4.0.5 / 4.0.7 / 3.1.7 | 4.0.6 / 4.0.8 / 3.1.8 |
| build_runner | 2.15.1 | 2.16.0 |
| Drift / drift_dev | 2.34.3 / 2.34.1+1 | 2.34.3 / 2.34.5 |
| SQLite Dart package | 3.5.0 | 3.5.2 |
| Firebase Core / Messaging | 4.12.1 / 16.4.3 | 4.14.0 / 16.6.0 |
| Sentry Dart / Flutter | 9.25.0 | 9.28.0 |
| SHA-2 / HMAC / HKDF | 0.10 / 0.12 / 0.12 | 0.11.0 / 0.13.0 / 0.13.0 |
| ChaCha20-Poly1305 / X25519 | 0.10 / 2 | 0.11.0 / 3.0.0 |
| Cloud reqwest / SQLx | 0.12 / 0.8 | 0.13.4 / 0.9.0 |
| Cloud base64 / Ed25519 / rand / tower-http | 0.22 / 2 / 0.8 / 0.6 | 0.23.1 / 3.0.0 / 0.10.2 / 0.7.0 |
| Android compile SDK | Flutter default, 36 | 37 |

The complete [direct-dependency inventory](direct-dependencies.csv) records 238 baseline package/dependency pairs plus four introduced direct dependencies, their declared constraints, previous and final lockfile versions and the stable registry target. Rust entries list all locked versions of a crate when different upstream consumers require different majors. An empty previous resolution means the package was not in the previous lockfile or had no committed lockfile; an empty previous constraint identifies an introduced direct dependency. `rand_core` is no longer a direct CLI dependency; the new direct `rand` 0.10.2 dependency supplies the OS random generator. Other new explicit dependencies are `hex` 0.4.3 in alera-core and Linux-only `keyring-core` 1.0.0 plus `dbus-secret-service-keyring-store` 1.0.1.

The obsolete `sqlite3_flutter_libs` package was removed: its selected EOL release is a no-op and SQLite 3.x owns native asset delivery. No application import depended on it. [Upstream explanation](https://pub.dev/packages/sqlite3_flutter_libs).

## Migration details

- The Rust pin is synchronized in both toolchain files, Cargokit configurations, CI, the Windows setup script and the Cloud build image. The Rust edition and profiles are unchanged.
- FRB was generated with version 2.13.0. The generated content hash remains `1213617933`, matching the original functional bridge API.
- New crypto APIs use fixed-size nonce conversions and `UnwrapErr(SysRng)`, retaining OS-backed randomness and the previous failure behavior. SHA-256 fingerprints remain lowercase hex. The existing cross-language known-answer vectors were not rewritten.
- Cloud enables reqwest's newly separate `form` feature and uses the current SQLx runtime/rustls feature names. System TLS is not introduced. Existing HTTP and PostgreSQL contracts remain the acceptance boundary.
- Firebase's new `deniedPermanently` authorization state maps to the existing denied permission state. A service-level test covers both denial variants.
- Native Firebase initialization can report missing configuration as `PlatformException`, not only `FirebaseException`. Startup and the background notification handler now tolerate both, preserving offline builds without Firebase resources. Two channel-level regression tests fail before the fix and pass afterward; this was exposed by the APK smoke test, not established as a newly introduced upstream regression.
- Android only changes `compileSdk`; existing minimum and target SDK expressions remain intact. Kotlin's generated local cache is ignored.
- The internal credential-entry adapter keeps existing service/user identifiers and recreates the Linux store on each attempt, so an initially unavailable store can recover. The private Linux fallback implementation and file permissions are unchanged.

## Intentional exceptions

| Dependency or tooling | Decision and evidence |
| --- | --- |
| `desktop_updater` | Keep 2.7.0. Stable 3.1.6 is excluded because v3 needs coordinated installer, recovery and signing changes. Track separately using the [upstream migration guide](https://github.com/MarlonJD/flutter_desktop_updater/blob/main/docs/migration/2.x-to-3.0.md). |
| Keyring on macOS and Windows | Keep 3.6.3 with the original Apple Keychain and Windows Credential Manager backends. SSH probes could not access an interactive credential store, so compatibility with the new native-store ecosystem was not certified. No real credentials were read or replaced. |
| Keyring on Linux | Migrate to keyring-core 1.0.0 and the Secret Service store 1.0.1. A synthetic old-write/new-read/new-write/old-read probe passed against the real Secret Service store; it removed only its synthetic entry. |
| Android AGP / Gradle / Kotlin | Keep 8.13.2 / 8.14.3 / 2.3.20. AGP 9.3.2 and Gradle 9.5.0 were tested: the standalone secure-storage probe works, but copied Cargokit fails parsing `android-37.0` at `compileSdkVersion.substring(8) as int`. Updating copied Cargokit is outside scope. The retained toolchain builds the app with compile SDK 37; Flutter emits future-support warnings. |
| Terminal forks | Existing path overrides and exact submodule commits are preserved, including the nested Ghostty checkout. Published pub.dev versions are not substitutes for those forks. |
| Multimedia | Preserve exact `media_kit` 1.2.6, `media_kit_libs_video` 1.0.7 and `media_kit_video` 2.0.1 with the coordinated native manifest, hashes and licenses. |
| Transitive dependency families | Do not force incompatible majors with overrides. See [Dart exceptions](dart-exceptions.csv), [runtime Rust exceptions](runtime-transitives.csv) and [Cloud Rust exceptions](cloud-transitives.csv). Rust files identify the upstream parent and required range; Dart records the solver's maximal resolvable version. |
| CocoaPods / Swift Package Manager | Keep the existing CocoaPods integration. Firebase reports that new CocoaPods releases end after October 2026, and Flutter warns about plugins without Swift Package Manager support. That packaging migration is separate from the current dependency update. |

## Validation evidence

Local logs are retained under `.dart_tool/dependency-upgrade/` in the implementation checkout and are intentionally not committed. The following results distinguish successful checks, known intermittent failures and the explicit scope exclusions above.

| Check | Result |
| --- | --- |
| Initial repository state | Clean; `make init-submodules` initialized only the required pinned submodules. |
| Baseline desktop | Analysis passed; 3,414 tests passed, one skipped. |
| Baseline mobile | Analysis passed; 629 tests passed, three skipped. |
| Baseline Rust and Cloud | Passed after supplying the missing Linux Vulkan shader compiler in an isolated tools directory. |
| Updated desktop analysis | Passed, including the final post-generation repeat. |
| Updated desktop tests | 3,414 passed and one skipped in the final complete run. A prior transient host-capability failure also passed alone. |
| Goldens | All four passed without updating images. |
| Updated mobile | Analysis passed; all 633 tests passed, three skipped, including four new Firebase compatibility cases. |
| Shared packages | Browser: 22 tests; configuration: 16 tests. Both analyses and enforced lockfile resolutions passed. |
| Native plugin manifests | Resolved and analyzed. |
| Standalone packager | Enforced lockfile resolution passed; verification produced all six runtime archives. |
| Dart generation | Desktop and mobile regenerated once per batch, normalized and formatted. Second generation produced zero source differences; FRB regeneration also reproduced byte-for-byte. |
| Rust format / Clippy | Workspace format and `cargo clippy --workspace --all-targets --locked -- -D warnings` passed. |
| Rust tests | All workspace suites passed except the documented PTY timing case under concurrent execution; that exact case passed alone. Includes 1,360 CLI unit tests, 240 core tests, 191 native tests and unchanged crypto vectors. |
| Cloud | Format, strict Clippy and 20 unit tests passed. All four PostgreSQL integration/contract tests passed against a dedicated PostgreSQL 17 container. Docker image built from the pinned Rust 1.98.0 Dockerfile. |
| Cross-language relay | Eight Dart clients exchanged 528 encrypted responses with the updated Rust runtime and local workerd. Runtime/mobile grant renewals and two durable-object evictions passed. The adversarial suite also passed: blocked handshake, unread output, six responsive peers and rapid connection replacement without stale ciphertext. Only synthetic identities and loopback endpoints were used. |
| Native dictation | Real inference through the generated FRB 2.13 Dart API passed on Linux and Windows with Vulkan and on macOS with Metal plus Core ML. All three returned the expected public-audio phrase, auto-detected English and reported 11,000 ms. The test loads the already-built native library directly; it does not use a mock, microphone, user recording or paid service. |
| Published mobile credential baseline | All 47 published mobile releases, from `v0.0.1-mobile` through `v0.32.1-mobile`, declare and lock secure storage 10.3.1. The old-write/new-read probes below therefore exercise the version shipped by every preceding mobile release, not only the implementation branch. |
| Secure storage Android | On an isolated API-35 emulator, a synthetic app using 10.3.1 seeded three credential shapes. Installing v11 over the same app without uninstalling preserved every value; new write/read/delete also passed. No user installation was replaced. |
| Secure storage iOS | The same old-write/new-read/new-write/delete sequence passed on iOS 26.5 Simulator. The fixture reported `ALERA_STORAGE_SEED_PASS` on 10.3.1 and `ALERA_STORAGE_UPGRADE_PASS` after upgrading in place to 11.0.0. The simulator screenshot backend failed, so the instrumented fixture returned only its result marker over loopback HTTP. |
| Linux | Native desktop debug build passed; native process (six cases), workbench, terminal input/clipboard and typography smoke tests all passed. |
| Android | Debug and release APKs built. Release native-library verification passed for armv7, arm64 and x86_64. After the Firebase bootstrap fix, the release app reaches the Pair Host screen on an empty isolated emulator without Firebase configuration. |
| macOS | Native desktop debug build passed, as did six native process cases, workspace UI, tray registration, Dock badge updates and hide-on-close. All 18 real terminal-host conformance cases passed, including PTY/protocol flow, restart recovery, session cleanup and live resource attribution. Native terminal selection, copy/paste shortcuts and Unicode clipboard also passed on a disposable GitHub-hosted runner. Uses an isolated Flutter 3.47.2 SDK. |
| Windows | Native desktop debug build and all six native process tests passed in a dedicated remote mirror and isolated SDK. All five Job Object lifecycle tests and 26 resource-sampling/attribution tests passed. All 18 full terminal-host conformance cases also passed on a disposable GitHub-hosted runner, with no failures or ignored cases. Native terminal selection, copy/paste shortcuts and Unicode clipboard passed on another disposable GitHub-hosted runner. The workspace UI smoke passed with the default renderer in the interactive graphical session, including asset images and sidebar layout. The first build attempt hit the resource compiler's path limit; successful local builds use the task-owned short `C:\q` Cargo prefix. A laptop reboot interrupted an intermediate run. |
| iOS | Final simulator debug and unsigned device release builds passed with the Firebase fix. An instrumented simulator copy with a distinct app identifier completed the real `main()`, rendered Pair Host after asynchronous loading, initialized native notifications and reported `ALERA_IOS_STARTUP_PASS`. No existing Alera installation was replaced. CocoaPods lockfiles match the build copies. |

The full Rust run reproduces `cancelling_active_worker_interrupts_before_idle_banner_delivery` from the repository's documented intermittent PTY failures. The isolated rerun passes without changing the test or runtime behavior. The desktop transient case is `does not split orchestration from an in-flight host without capability`; it also passes in isolation. These are reported rather than silently counted as a clean first run.

The local macOS native clipboard test stopped at its explicit disposable-desktop guard before accessing the clipboard. That guard was not bypassed on the user's desktop; the test subsequently passed on a disposable GitHub-hosted macOS runner. Native clipboard behavior also passed on Linux under an isolated Xvfb display and on a disposable GitHub-hosted Windows runner. Live production push delivery, microphone capture, dictation against paid providers and signed device installation are not exercised by these isolated checks. The local dictation probe covers real WAV decoding, native inference and the Dart/Rust bridge, not the microphone UI.

The workspace UI smoke test uses in-memory Drift repositories and a simulated terminal-host boundary. It validates the shared UI and SQLite flow, not a live PTY. The Rust host conformance suite exercises real PTYs, socket messages, restart recovery and resource attribution separately. On Windows, its home-isolation helper explicitly cannot guarantee isolation from the user's agent-hook configuration, so that suite ran on a disposable GitHub-hosted account rather than the user's account.

The first Windows UI run failed in SSH session 0 with `No Impeller context is available` and a sidebar overflow. A diagnostic launch with Impeller disabled also reported `EGL Error: Context Lost`; its driver could not complete the integration-test handshake, so it is not a passing retry. The unchanged smoke test then passed in graphical session 1 with the default renderer: `All tests passed!`, exit code 0 at 2026-08-30 22:34:37 UTC. This validates the UI without changing the product's renderer configuration. Two earlier graphical attempts stopped in the temporary PowerShell runner before launching the test; those harness failures are not counted as product test results. The on-demand, unelevated scheduled task had no triggers and was removed after completion; no owned app process remained. Flutter documents the [Windows renderer switch](https://docs.flutter.dev/perf/impeller#windows) and the [limitations of Impeller's software fallback](https://github.com/flutter/flutter/issues/187763).

## Final hosted acceptance and cleanup

The remaining environment-dependent acceptance checks passed on disposable GitHub-hosted accounts. All accepted dependency migrations and required isolated validations are complete, subject to the documented exceptions and intermittent-test qualifications above.

| Check | Result and hosted evidence |
| --- | --- |
| macOS native clipboard | One test passed: [job 99356793819](https://github.com/leynier/alera/actions/runs/33348376076/job/99356793819), commit `d1d9455c`. The overall initial run failed because of its separate Windows jobs. |
| Windows native clipboard | One test passed: [job 99357853136](https://github.com/leynier/alera/actions/runs/33348757871/job/99357853136), commit `6e2ff310`. The native build and enforced lockfile check also passed. |
| Windows full terminal host | All 18 tests passed, none failed or ignored: [job 99358022864](https://github.com/leynier/alera/actions/runs/33348819819/job/99358022864), commit `ebb95d95`. |

The clipboard jobs set `ALERA_NATIVE_TEST_CLIPBOARD=1` only on their disposable desktops and ran `flutter test integration_test/terminal_input_native_test.dart -d <platform> --no-pub --reporter expanded`. The Windows host job ran `cargo test --manifest-path rust/Cargo.toml -p alera-cli --test terminal_host_conformance --locked -- --test-threads=2`. The [hosted validation record](hosted-validation.json) preserves exact commit IDs, job conclusions, test counts and SHA-256 hashes of the downloaded logs. The tested product tree is identical across the implementation and retry commits; only the temporary workflow and report differed.

After collecting the results, `.github/workflows/dependency-upgrade-validation.yml` was removed from the delivery branch and workflow ID `346239218` was disabled. No temporary validation workflow remains configured. Existing workflows are preserved, with only the planned Rust version pins changed by this upgrade. Historical runs remain available as evidence; the disposable jobs have all completed. No release, deployment or merge was performed.

The newer native keyring ecosystem on macOS and Windows is a deferred dependency migration, not a partially applied change: the existing 3.6.3 backends remain in use. Paid-provider dictation, live production push and signed device deployment are not substitutes for these isolated acceptance checks and were not performed.

The first hosted Windows attempts stopped before executing tests because of temporary workflow configuration: a global Ninja override prevented Flutter from locating the C++ compiler, and Git Bash converted the MSVC `/Z7` flag into a filesystem path for the Rust job. The successful retries retain Flutter's existing build environment and run the Rust command from PowerShell. These are harness failures, not passing tests or identified dependency regressions; no product code was changed to address them. The successful clipboard builds still log upstream media CMake policy warnings, a non-fatal Windows Cargokit symlink lookup error, and macOS updater privacy-manifest and foregrounding warnings; neither job suppressed test failures.

## Security audit

OSV was queried for 1,026 unique ecosystem/package/version combinations in the final owned lockfiles. Pub's final outdated reports mark no selected package as affected by an advisory. Two Rust findings remain, both already present at the same version in the baseline:

- `paste` 1.0.15 via `simba` is unmaintained, with no patched release. It is an upstream transitive dependency; replacing a vendored implementation or forcing a fork is outside scope. [RUSTSEC-2024-0436](https://rustsec.org/advisories/RUSTSEC-2024-0436.html).
- `rsa` 0.9.10 via jsonwebtoken and Cloud's test fixtures has the Marvin timing advisory, with no patched stable version. Production Cloud uses public-key Google JWT verification; private RSA signing in this repository is confined to synthetic test fixtures. This does not make the package advisory disappear, and future private-key use must not be introduced without resolving it. [RUSTSEC-2023-0071](https://rustsec.org/advisories/RUSTSEC-2023-0071.html).

## Reproduction

Use Flutter 3.47.2 / Dart 3.13.2, Rust 1.98.0 and the platform build prerequisites. CI's exact commands remain in `.github/workflows/pr.yml`, `desktop-build.yml`, `mobile-build.yml` and `cloud.yml`. On Linux, Vulkan-enabled Whisper also needs `glslc` on PATH and its shared library discoverable; this run unpacked those tools locally rather than changing system packages.

For bridge regeneration, install `flutter_rust_bridge_codegen` with `cargo +1.98.0 install flutter_rust_bridge_codegen --version 2.13.0 --locked --root .dart_tool/frb-codegen`, put that directory's `bin` on the command's PATH, then run `make frb-generate`. Do not use an older globally installed generator. The bridge bindings are committed and CI does not regenerate them.

The manual [native dictation probe](whisper_smoke.dart) uses the public [whisper.cpp JFK WAV fixture](https://github.com/ggml-org/whisper.cpp/blob/master/samples/jfk.wav), SHA-256 `59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e`. The Tiny model and macOS Core ML encoder archive match Alera's existing model manifest: SHA-256 `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` and `c88cbd2648e1f5415092bcf5256add463a0f19943e6938f46e8d4ffdebd47739`. Extract `ggml-tiny-encoder.mlmodelc` beside `ggml-tiny.bin` on macOS. Run from the repository root with absolute paths: `dart --packages=.dart_tool/package_config.json docs/dependency-upgrade-2026-08/whisper_smoke.dart <native-library> <ggml-tiny.bin> <jfk.wav>`. It uses the existing platform build and does not regenerate or rebuild the app. Use only public test audio because the debug native library may log decoded tokens.

```sh
make init-submodules
flutter pub get --enforce-lockfile
dart run build_runner build
dart tool/ci/normalize_generated_eof.dart
dart format lib test
flutter analyze --no-pub
flutter test --no-pub --exclude-tags golden
flutter test --no-pub test/golden
(cd mobile && flutter pub get --enforce-lockfile && dart run build_runner build && dart ../tool/ci/normalize_generated_eof.dart . && dart format lib test && flutter analyze --no-pub && flutter test --no-pub)
(cd rust && cargo fmt --all --check && cargo clippy --workspace --all-targets --locked -- -D warnings && cargo test --workspace --locked)
(cd cloud && cargo fmt --all --check && cargo clippy --workspace --all-targets --locked -- -D warnings && cargo test --workspace --locked)
docker build --file cloud/Dockerfile cloud
(cd edge && bun install --frozen-lockfile)
RUSTUP_TOOLCHAIN=1.98.0 node edge/tool/relay_integration.mjs 20
RUSTUP_TOOLCHAIN=1.98.0 node edge/tool/relay_integration.mjs 20 faults
```

Run the four ignored Cloud PostgreSQL tests with `TEST_DATABASE_URL` pointing exclusively to an isolated test database. Never use production. Remote platform smoke tests and credential-store certification require the appropriate desktop session; a platform or interactive check that cannot run must stay explicitly pending.
