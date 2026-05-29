# Contributing To Alera

Thanks for contributing to Alera.

## Before You Start

- Keep changes scoped to a clear user-facing improvement, bug fix, refactor, or infrastructure improvement.
- Alera targets macOS, Windows, and Linux. Avoid platform-specific assumptions in shortcuts, file paths, shell behavior, and process execution.
- UI work must follow `AGENTS.md` and `docs/ui-styleguide.md`.
- GitHub Actions work must follow `.github/AGENTS.md`; release scripts must follow `tool/release/AGENTS.md`.

## Local Setup

```bash
git submodule update --init third_party/xterm third_party/dart_terminal
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

Alera runs as a Flutter desktop app plus a bundled Dart CLI named `alera`. The app owns UI state and terminal surfaces; the CLI sidecar runs `alera terminal-host`, owns the long-lived PTY sessions, writes host control metadata, and keeps terminal checkpoints alive after the app is closed.

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

`make help` lists the available repository targets. `make host-debug` runs `alera terminal-host` in the foreground using the platform app-support runtime directory so stdout/stderr stay visible. `make host-debug-observe` does the same with a Dart VM service on `127.0.0.1:8181` for debugger attach. If a platform's app-support location differs from the default, set `ALERA_APP_SUPPORT_DIR` before running the target. Foreground host runs accept `ALERA_HOST_EMPTY_SHUTDOWN_SECONDS`, `ALERA_HOST_DETACHED_SHUTDOWN_SECONDS`, and `ALERA_HOST_SCROLLBACK_BYTES`; these are forwarded to `alera terminal-host` for lifecycle and scrollback debugging.

`make app-debug-host-observe` generates `.dart_tool/alera-debug-host` (or `.exe` on Windows) and runs the Flutter app with `ALERA_CLI_PATH` pointing to that wrapper. Use it when the bug only appears when the app launches the host itself. Avoid `--pause-isolates-on-start` unless you also raise the app startup timeout, because the app waits for the host control file before attaching terminal sessions.

Use `make debug-processes` to confirm process separation. During a healthy app run, the UI process should be the Flutter app and the persistent sidecar should be a separate `alera terminal-host` process. Use `make host-stop` only when intentionally ending the current debug host for this app id.

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
dart run tool/quality/coverage_report.dart --input coverage/lcov.info --min-lines 65 --worst 25
```

The coverage report excludes generated `*.g.dart` and `*.mapper.dart` files so the gate reflects maintained source code instead of build output.

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

## Release Process

Version bumps, release tags, update manifests, and published assets are maintainer-managed through GitHub Actions. Do not include release version changes in normal contributions unless a maintainer asks for them.
