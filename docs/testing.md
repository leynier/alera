# Testing Alera

This guide defines the default testing layers for Alera and the commands that should be used before shipping features, UI changes, and refactors.

## Test Layers

- Unit tests cover pure domain logic, controllers, repositories, command construction, parsers, and platform branches with the smallest possible setup.
- Widget tests cover user-visible UI state, layout contracts, shortcuts, and interactions inside a focused widget tree.
- Golden tests use `alchemist` to snapshot important UI states. They are best for design-system components and stable product surfaces where visual regressions matter.
- E2E tests use Flutter `integration_test` to run complete desktop flows through the real app shell with temporary storage and fake external boundaries.
- Manual desktop builds still matter when a change touches packaging, release behavior, native plugins, platform file handling, or terminal process behavior.

## Local Commands

Run the fast checks first:

```bash
dart format --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test --exclude-tags golden
```

Run unit and widget tests with line coverage:

```bash
flutter test --coverage --exclude-tags golden
dart run tool/quality/coverage_report.dart --input coverage/lcov.info --min-lines 65 --worst 25
```

Run golden tests:

```bash
flutter test --tags golden
```

Update golden files only when the visual change is intentional:

```bash
flutter test --update-goldens test/golden
```

Run desktop E2E locally on the current platform:

```bash
flutter test integration_test -d macos
```

Use `-d linux` or `-d windows` on those platforms. The checked-in E2E flow must use temporary directories, temporary databases, fake process runners, and fake terminal runtimes unless the test explicitly needs a native boundary.

## Coverage

`tool/quality/coverage_report.dart` reads `coverage/lcov.info`, ignores generated `*.g.dart` and `*.mapper.dart` files, prints total line coverage, groups coverage by area, and lists the files with the most missed lines. The PR gate starts at 65% line coverage so the current suite has a useful floor without blocking incremental test expansion.

When coverage drops, use the "worst files by missed lines" section to decide whether to add focused unit tests, widget tests, or an E2E path. Do not chase coverage by snapshotting implementation details; cover behavior that would catch a real regression.

## Golden Tests

Golden tests live under `test/golden/` and use `alchemist`. The project config disables platform-readable goldens and keeps CI goldens stable across hosts. The first snapshots cover core design-system controls and the welcome dashboard in desktop and compact states.

Good golden candidates:

- Design-system components in `lib/src/design_system/`.
- Stable shell/dashboard states.
- Dialogs with meaningful layout variants.
- Error and empty states that are easy to regress visually.

Poor golden candidates:

- Highly animated or cursor-heavy states.
- Real terminal rendering.
- Native file picker flows.
- Screens that depend on wall-clock time, network data, or host fonts outside the configured test theme.

## E2E Tests

E2E tests live under `integration_test/`. They should prove full product flows that cross multiple widgets and application providers, such as adding a project, selecting a workspace, and opening terminal tabs.

Keep E2E tests deterministic:

- Use temporary project folders.
- Override `aleraDatabaseProvider` with a temporary or in-memory database.
- Override `processRunnerProvider` when a flow should not execute real commands.
- Override `terminalRuntimeProvider` when a flow only needs terminal UI behavior.
- Avoid network access.
- Avoid native file pickers; paste paths directly into dialogs.

## Terminal Host Checks

Terminal persistence changes should include focused unit tests for the host client/session boundary and at least one manual or integration smoke on the current desktop platform: start a long-running terminal command, close Alera, reopen it, and confirm the terminal output continues under the same workspace tab. Explicit tab or workspace close must be checked separately because it should terminate the durable session instead of detaching.

Lifecycle changes must cover both host timeout paths. With the app closed and no running sessions, the host should stop after the configured empty-host delay. With the app closed and at least one running session, the host should keep the session alive until the configured detached-session delay, then terminate the PTY, write a final checkpoint, and delete `host.json`. Use small values from Settings during manual smoke tests so the behavior can be observed without waiting for the production defaults.

Scrollback changes must check both rendering and host memory behavior. The terminal row scrollback controls xterm history in the app. The host scrollback size controls how many bytes are retained for detached-session snapshots and checkpoints; tests should prove the buffer is trimmed to the configured byte limit and that checkpoints remain restorable after restart.

For local sidecar smoke tests, build the Rust CLI sidecar with the makefile (which drives cargo and stages the binary):

```bash
make cli-build
make cli-help
```

`make cli-build` runs `cargo build --release -p alera-cli` and stages the single binary into `.dart_tool/alera/alera` (`.dart_tool/alera/alera.exe` on Windows); `make cli-help` runs the staged binary's `--help`. The Rust crate also has its own checks via `make rust-test` (`cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`).

The repository `makefile` exposes cross-platform debug targets around the same flow. `make help` lists available targets. For foreground host debugging, `make host-debug` and `make host-debug-observe` accept `ALERA_HOST_EMPTY_SHUTDOWN_SECONDS`, `ALERA_HOST_DETACHED_SHUTDOWN_SECONDS`, and `ALERA_HOST_SCROLLBACK_BYTES`, which are forwarded to `alera terminal-host`.

## Mocking

Alera currently favors small hand-written fakes for repositories, process runners, and terminal runtimes because those boundaries are domain-specific and easy to inspect. `mocktail` is still a good Dart package when a test needs many interaction assertions or when a collaborator has a broad interface that would make a fake noisy. Prefer explicit fakes for durable behavior tests and use mocks sparingly for call verification.
