# Alera

Alera is a Flutter desktop Agentic Development Environment focused on projects,
workspaces, and terminal-first agent workflows. Agents are expected to run
through their own CLI tools inside Alera-managed terminals instead of through an
embedded adapter-specific chat backend.

## Current Scope

- Project registry for local Git repositories.
- Workspace management backed by Git worktrees for linked branches.
- Split terminal workbench with persistent tabs and layouts.
- Native terminal runtime using `ghostty_vte_flutter`, `portable_pty`, and
  `xterm` fallback infrastructure.
- Local Sembast persistence for projects, workspaces, terminal tabs, layouts,
  and view preferences.
- Dark-mode-only Flutter UI using the Alera design tokens and theme.

## Project Layout

- `lib/src/app`: bootstrap, dependency providers, and theme setup.
- `lib/src/shared`: shared infrastructure such as process and storage helpers.
- `lib/src/features/projects`: project registry and project sidebar UI.
- `lib/src/features/workbench`: workspaces, terminal tabs, split layouts, and
  terminal runtime.
- `lib/src/features/shell`: top-level application shell.
- `test/unit` and `test/widget`: focused unit and widget coverage for the
  active ADE surface.

## Desktop Targets

Configured targets:

- macOS

Bundle/application org is set to `dev.leynier`.

## Run Locally

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

## Reference Projects

Reference projects live under `reference_projects/`. They are non-Flutter
agentic development and orchestration references used for product and
infrastructure inspiration. Alera should remain terminal-first and should not
depend on any reference project at runtime.
