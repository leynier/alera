# Alera

Alera is a Flutter desktop orchestrator for `codex app-server`, currently configured for macOS.

## Current Scope (v1 foundation)
- `codex app-server` bridge over JSON-RPC (`stdio`) with framed message parsing.
- Feature-first app architecture under `lib/src/features/*`.
- Session lifecycle with repository/worktree modes.
- Plan mode vs normal mode execution handling.
- Approval engine with allowlist precedence: `session > project > global`.
- Dual model selection (`planner` and `executor`) in session requests.
- MCP service abstraction through app-server methods.
- Native slash command layer with built-ins such as `/new`, `/compact`, `/review`, `/plan`, `/skills`, and `/apps`.
- Custom prompt commands discovered from `<workspace>/.codex/prompts/*.md` and `$CODEX_HOME/prompts/*.md`.
- Embedded terminal with `xterm` + `flutter_pty` and automatic fallback to process pipes.
- Desktop-safe persistence baseline (`drift`, secure storage, shared prefs fallback).

## Project Layout
- `lib/src/app`: bootstrap, routing, dependency providers.
- `lib/src/shared`: infra/services shared across features.
- `lib/src/features/*`: feature modules (`session`, `worktree`, `terminal`, `approvals`, `commands`, `mcp`, etc.).
- `test/unit`: unit tests for parser, approvals, commands, worktree, and branch naming.

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

## Notes
- This repository expects `codex` CLI with `codex app-server` available in `PATH`.
- Auto-installer for Codex CLI is intentionally out of scope for this phase.
