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
dart format --set-exit-if-changed lib test tool
flutter analyze
flutter test
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
- include platform-specific notes when behavior differs by OS
- include an AI review summary and a basic security audit when an AI agent helped with the change

If there is no visual change, say that explicitly in the PR description.

## Release Process

Version bumps, release tags, update manifests, and published assets are maintainer-managed through GitHub Actions. Do not include release version changes in normal contributions unless a maintainer asks for them.
