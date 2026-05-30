# Alera

TODO: Add project badges for supported platforms, release status, and repository metadata once the final links are available.

Alera is a terminal-first Agentic Development Environment built with Flutter for performance, developer velocity, and true cross-platform desktop support.

It helps you organize local project folders, clone Git repositories, create isolated Git worktree workspaces when Git is available, and run your preferred CLI coding agents in persistent terminal sessions.

## What is Alera?

Alera is for developers who use CLI-based coding agents and want a native-feeling desktop environment around them.

Instead of embedding a specific chat backend, Alera stays terminal-first: your agents run through their own CLI tools, inside Alera-managed terminals.

## Why Alera?

- **Terminal-first by design** — Bring your own CLI agents instead of being locked into one AI backend.
- **Flutter desktop performance** — Built with Flutter to pursue a fast, native-feeling, maintainable, cross-platform desktop experience.
- **Worktree-native workflows** — Keep tasks, branches, and agent runs isolated with Git worktrees for Git-backed projects.
- **Project and workspace organization** — Manage local folders, cloned repositories, and their workspaces from one app.
- **Persistent workspace tabs** — Keep agent sessions, terminal tabs, panes, and layouts organized.
- **Cross-platform** — Designed for macOS, Windows, and Linux.

## Features

### Project registry

Add existing local folders or clone Git repositories from one place. Non-Git folders get a primary workspace, while Git-backed projects can also create linked workspaces.

### Worktree-backed workspaces

Create linked workspaces backed by Git worktrees for Git-backed projects so each branch, task, or agent run can stay isolated.

### Terminal-first agent workflows

Run CLI agents directly in Alera-managed terminals without an adapter-specific chat backend.

### Workspace workbench

Use persistent workspace tabs, terminal sessions, panes, and layouts for parallel agent workflows.

### Native Flutter desktop app

Alera is built in Flutter to balance performance, UI consistency, developer productivity, and multiplatform delivery.

### Release and update checks

Alera can check for new desktop releases and guide users to manual downloads.

TODO: Add the final public download and update flow once release signing and platform trust requirements are complete.

## Supported CLI agents

Alera is intended to support any CLI-based coding agent, including:

- Claude Code
- Codex
- Amp
- Antigravity CLI
- OpenCode
- Cursor CLI
- GitHub Copilot CLI

TODO: Confirm and document any agent-specific setup instructions.

## Install

TODO: Add public download links when release artifacts are available.

### Run from source

Building Alera requires a Rust toolchain (`rustup`) in addition to the Flutter SDK: git operations run in a Rust crate (`rust/`) compiled into the app through `flutter_rust_bridge`.

```bash
git submodule update --init third_party/xterm third_party/dart_terminal
flutter pub get
flutter run -d macos
```

Regenerate the Rust bindings after changing the Rust API (`rust/src/api`) with `make frb-generate`.

TODO: Add Windows and Linux local run notes if extra setup is required.

## Current status

Alera currently includes:

- Local project registry for folders and cloned Git repositories.
- Git worktree-backed workspace management for Git-backed projects.
- Split workspace workbench.
- Persistent workspace tabs and layouts.
- Native terminal runtime using `ghostty_vte_flutter`, `portable_pty`, and `xterm` fallback infrastructure.
- Local Drift/SQLite persistence for projects, workspaces, workspace tabs, layouts, settings, and view preferences.
- Dark-mode Flutter UI using Alera design tokens and theme.
- Desktop release checking.

## Inspired by great open source projects

Alera is inspired by several excellent open source projects in the agentic development and developer tooling space.

Special thanks to:

- **Orca** — A major inspiration for agentic development workflows, multi-agent workspaces, and worktree-oriented product thinking.
- **Ghostty** — Inspiration for fast, high-quality terminal experiences.
- **xterm.js** — Inspiration and ecosystem reference for terminal rendering and compatibility.
- **Flutter** — The foundation that makes Alera's cross-platform desktop UI possible.
- **Drift** — Used for local persistence.
- **desktop_updater** — Used behind Alera's desktop update boundary.

TODO: Add links to each project and verify exact dependency/inspiration wording.

## Developing

### Project layout

- `lib/src/app`: bootstrap, dependency providers, and theme setup.
- `lib/src/shared`: shared infrastructure such as process and storage helpers.
- `lib/src/features/projects`: project registry and project sidebar UI.
- `lib/src/features/updater`: update archive parsing, update controller, and desktop updater integration.
- `lib/src/features/workbench`: workspaces, workspace tabs, split layouts, and terminal runtime.
- `docs/architecture.md`: current architecture glossary and naming rules.
- `docs/testing.md`: unit, widget, golden, E2E, and coverage workflow.
- `lib/src/features/shell`: top-level application shell.
- `test/unit` and `test/widget`: focused unit and widget coverage for the active ADE surface.

### Checks

```bash
flutter analyze
flutter test --coverage --exclude-tags golden
dart run tool/quality/coverage_report.dart --input coverage/lcov.info --min-lines 65 --worst 25

The coverage report ignores generated `*.g.dart` and `*.mapper.dart` files so the percentage tracks maintained application code.
```

Use `flutter test --tags golden` for visual regression tests and `flutter test integration_test -d macos` for local desktop E2E smoke coverage. See `docs/testing.md`.

## Desktop targets

Alera targets:

- macOS
- Windows
- Linux

Released builds use bundle/application identifier `dev.leynier.alera` and the display name `Alera`. Local builds default to the `dev` flavor (`dev.leynier.alera.dev`, display name `Alera Dev`) so a development build can coexist with an installed release without sharing user data. Set `ALERA_FLAVOR=release` to opt a local build back into the release identifier.

## Releases and updates

Public release cuts are maintainer-managed through GitHub Actions. Stable builds can detect new releases and open the manual download page; automatic stable installation stays disabled until the release builds are signed and trusted for the target platform. Release candidate builds may opt into automatic installation through explicit build flags. Stable builds read `https://updates.alera.build/app-archive.json`; release candidate builds read `https://updates.alera.build/app-archive-rc.json`. Updater payloads are hosted in Cloudflare R2 under `updates/stable/` and `updates/rc/`; GitHub Releases remain the manual download surface.

## Reference projects

Reference projects live under `reference_projects/`. They are non-runtime references for agentic development and orchestration patterns. Alera should remain terminal-first and should not depend on any reference project at runtime.
