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
flutter run -d macos
```

To develop or review shared UI in isolation, launch the widget previewer (requires Chrome):

```bash
flutter widget-preview start
```

Shared components live in `lib/src/design_system/` (prefixed `Alera`) with co-located `*.preview.dart` files and an aggregate gallery in `lib/src/design_system/gallery/`. See `docs/ui-styleguide.md`.

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
