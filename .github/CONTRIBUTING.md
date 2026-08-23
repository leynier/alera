# Contributing To Alera

Thanks for contributing to Alera.

## Before You Start

- Keep changes scoped to a clear user-facing improvement, bug fix, refactor, or infrastructure improvement.
- Alera targets macOS, Windows, and Linux. Avoid platform-specific assumptions in shortcuts, file paths, shell behavior, and process execution.
- UI work must follow `AGENTS.md` and `docs/ui-styleguide.md`.
- GitHub Actions work must follow `.github/AGENTS.md`; release scripts must follow `tool/release/AGENTS.md`.

## Local Setup

All platforms require Flutter 3.44.8 or newer with Dart 3.12.1 or newer, Git, Rustup, and Zig 0.16.0. CI is pinned to Flutter 3.44.8. Run `make init-submodules` to initialize only the two source dependencies required by the Flutter package; the optional repositories under `reference_projects/` are not part of the build.

### Windows

Install Visual Studio 2022 with the **Desktop development with C++** workload and a Windows 10 or 11 SDK, Git for Windows, Flutter, and Rustup. PowerShell 7 is recommended. The repository setup checks those prerequisites, enables Git long paths, installs Zig, LLVM, and the pinned Vulkan SDK when requested, configures LLVM headers for Bindgen, pins native builds to the supported Visual Studio 2022 CMake generator, repairs nested submodules, resolves dependencies, and runs the native-asset preflight:

```powershell
pwsh -File tool/development/setup_windows.ps1 -InstallMissingTools
flutter run -d windows
```

Use `pwsh -File tool/development/setup_windows.ps1 -CheckOnly` for a read-only prerequisite check. The first native preflight can spend several minutes compiling Ghostty without output. GNU Make is optional for initial setup; install it if you want to use the convenience targets documented below.

### Linux

On Ubuntu and Debian, install the native dependencies required by the Linux desktop build:

```bash
sudo apt-get update
sudo apt-get install -y \
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  libwebkit2gtk-4.1-dev \
  libjson-glib-dev \
  libsecret-1-dev \
  libsqlite3-dev \
  libssl-dev \
  libepoxy-dev \
  libmpv-dev \
  libvulkan-dev \
  glslc
```

These packages provide the compiler toolchain and the native browser, video, storage, security, and Vulkan compute libraries used by the desktop app. Cargo builds outside Flutter should set `VULKAN_SDK=/usr`.

### Common setup

```bash
make init-submodules
flutter pub get
flutter analyze
flutter test
make app-debug
```

To develop or review shared UI in isolation, launch the widget previewer (requires Chrome):

```bash
flutter widget-preview start
```

Shared components live in `lib/src/design_system/` (prefixed `Alera`) with co-located `*.preview.dart` files and an aggregate gallery in `lib/src/design_system/gallery/`. See `docs/ui-styleguide.md`.

## Debugging The App And CLI

Alera runs as a Flutter desktop app plus a bundled Rust CLI named `alera`. The app owns UI state and terminal surfaces; the CLI sidecar runs `alera runtime-host`, owns runtime Projects/Workspaces/Tabs graph state plus long-lived PTY sessions, writes host control metadata, and keeps terminal checkpoints alive after the app is closed. `alera terminal-host` is kept as a compatibility alias.

Use the lowercase repository `makefile` for the standard debug flows. These targets intentionally call Dart tooling instead of inline shell snippets, so the same commands work from PowerShell 7 on Windows and from normal Linux/macOS shells:

```bash
make help
make app-debug
make cli-build
make cli-help
make app-debug-bundled-cli
make host-debug
make host-debug-observe
make app-debug-host-observe
make debug-processes
```

`make app-debug` runs `flutter run` for the current desktop platform (`macos`, `windows`, or `linux`) with the normal development fallback for the CLI. Override the device with `APP_DEVICE=<flutter-device-id>` when targeting a different Flutter desktop device. `make cli-build` compiles the sidecar into `.dart_tool/alera`, and `make app-debug-bundled-cli` runs the app while forcing it to resolve that compiled CLI bundle. Use this when validating behavior closer to a packaged app.

`make help` lists the available repository targets. `make host-debug` runs the runtime host in the foreground using the platform app-support runtime directory so stdout/stderr stay visible. `make host-debug-observe` does the same with a Dart VM service on `127.0.0.1:8181` for debugger attach. If a platform's app-support location differs from the default, set `ALERA_APP_SUPPORT_DIR` before running the target. Foreground host runs accept `ALERA_HOST_EMPTY_SHUTDOWN_SECONDS`, `ALERA_HOST_DETACHED_SHUTDOWN_SECONDS`, and `ALERA_HOST_SCROLLBACK_BYTES`; these are forwarded to the runtime host for lifecycle and scrollback debugging.

`make app-debug-host-observe` generates `.dart_tool/alera-debug-host` (or `.exe` on Windows) and runs the Flutter app with `ALERA_CLI_PATH` pointing to that wrapper. Use it when the bug only appears when the app launches the host itself. Avoid `--pause-isolates-on-start` unless you also raise the app startup timeout, because the app waits for the host control file before attaching terminal sessions.

Use `make debug-processes` to confirm process separation. During a healthy app run, the UI process should be the Flutter app and the persistent sidecar should be a separate `alera runtime-host` process; `alera terminal-host` may appear only for older launchers or compatibility checks. Use `make host-stop` only when intentionally ending the current debug host for this app id.

For landing page work:

```bash
cd landing
bun install
bun run build
```

## Branch Naming

Use a clear, descriptive branch name.

Good examples:

- `fix/windows-path-open-workspace`
- `feat/update-settings-panel`
- `docs/contributor-guide`

Avoid vague names like `misc`, `changes`, or `test`.

## Before Opening A PR

Run the relevant checks:

```bash
dart format --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test --coverage --exclude-tags golden
dart run tool/quality/coverage_report.dart --input coverage/lcov.info --min-lines 100 --worst 25
```

The coverage report requires 100% line coverage for maintained domain sources under `lib/src/features/**/domain/`. Generated mapping/provider output is excluded; presentation, infrastructure, and native surfaces are validated by the widget, golden, E2E, integration, Rust, and native build checks that match those layers.

For visual UI changes, run the golden suite and update snapshots only when the visual diff is intentional:

```bash
flutter test --tags golden
flutter test --update-goldens test/golden
```

For app-shell flows that cross dialogs, persistence, workspaces, or terminal tabs, run the desktop E2E suite on the platform you touched:

```bash
flutter test integration_test -d macos
```

If your change touches a desktop platform or release behavior, run the relevant build:

```bash
flutter build macos
flutter build windows
flutter build linux
```

If your change touches `landing/`, run:

```bash
cd landing
bun run build
```

## Pull Requests

Each pull request should:

- explain the user-visible change
- stay focused on one topic when possible
- include screenshots or screen recordings for UI changes
- include tests for behavior changes and bug fixes
- include golden updates for intentional visual changes
- include platform-specific notes when behavior differs by OS
- include an AI review summary and a basic security audit when an AI agent helped with the change

If there is no visual change, say that explicitly in the PR description.

### Merge Queue

Mergify validates pull requests in batches of two to four. When only one pull request is eligible, the queue waits up to 60 minutes for a second entry before starting the speculative checks. A maintainer can queue another ready pull request to start the batch sooner, but unrelated or unready changes must not be used to bypass the required checks.

## Release Process

Version bumps, release tags, update manifests, and published assets are maintainer-managed through the **Cut Release** GitHub Actions workflow. The workflow detects desktop and mobile changes independently and derives their SemVer bumps from Conventional Commit metadata. Do not include release version changes in normal contributions unless a maintainer asks for them.

A non-dry cut must start at the current `main` commit. Its first run creates or reuses an immutable `release/version-*` pull request containing the version files and `tool/release/prepared_release.json`, then explicitly dispatches the required pull request checks. Mergify queues that bot-owned pull request after its checks pass. The merge event starts a separate Cut Release run, revalidates the plan against the merge parent, and builds, tags, and publishes only from the exact merged commit. A dry run only writes the plan summary and never creates a branch, pull request, tag, or release.

### Main Ruleset Rollout

Do not activate the `main` ruleset until the release-writer pull request has merged and its writer path is present on `main`.

1. Run **Cut Release** on `main` with `dry_run=true`, preserve its successful run ID, and confirm the run title contains `dry_run=true`.
2. Run `dart tool/github/main_ruleset.dart --repository leynier/alera --dry-run-run-id <run-id>` and review the exact payload. This preflight verifies the merged writer, successful dry run, live GitHub App IDs, and current ruleset state without changing the repository.
3. Run the same command with `--apply`. The script creates the ruleset only when no repository ruleset exists, refuses to overwrite drift, and verifies the effective rules on `main`.
4. Prove an ordinary direct push is rejected with a controlled empty-tree commit. The command below does not change the checkout or files. If GitHub unexpectedly accepts it, leave the harmless empty commit in history, fix the ruleset through the API or settings, and do not force-push it away.

```bash
git fetch origin main
probe_sha="$(printf '%s\n' 'test: verify main ruleset rejects direct push' | git commit-tree "$(git rev-parse 'origin/main^{tree}')" -p origin/main)"
if git push origin "$probe_sha:refs/heads/main"; then
  echo 'ERROR: main accepted an ordinary direct push' >&2
  exit 1
fi
```

5. Queue an existing eligible pull request that does not touch backend or native surfaces. Verify `pr-ready` passes on its head, Mergify creates the queue candidate, `queue-ready` passes, and Mergify merges it. Keep issue #489 open until both this queued-merge proof and the rejected direct-push proof are recorded.
