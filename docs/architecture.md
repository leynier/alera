# Architecture

This document records the current product and code naming used by Alera. It is intentionally short and should stay aligned with implemented behavior.

## Naming Glossary

- `Project`: a local project path registered in Alera. It can be an existing local folder or a Git repository cloned from a URL; only Git-backed projects support linked workspaces.
- `Workspace`: a working context inside a project. A workspace points at one filesystem path and may point at one Git branch. The primary workspace points at the registered project path; linked workspaces point at Git worktrees and exist only for Git-backed projects.
- `Worktree`: the Git mechanism used to create an isolated checkout for a linked workspace. Use this term only for Git/filesystem behavior, not for the Alera UI container. Folder-only projects do not use worktrees.
- `Workbench`: the main interactive area for an active workspace. It owns pane layout, active group selection, and workspace tabs. A project may be active while no workspace is selected; in that state the shell shows an empty workspace surface and workspace-scoped panels should render without workspace context.
- `WorkbenchPaneGroup`: one pane in the split layout. It contains an ordered list of workspace tab ids and one active tab id.
- `WorkspaceTab`: the domain concept for a tab inside a workspace. It is intentionally broader than terminal because future tabs may represent editors, browsers, previews, or other surfaces.
- `TerminalSession`: the runtime process/PTY state attached to a terminal workspace tab. Terminal sessions are owned by the durable terminal host and are reattached by `terminalSessionId`; they are not persisted tab records.
- `SidebarTerminalTabRow`: the sidebar projection for terminal workspace tabs. The sidebar does not render every workspace tab type by default.
- `AgentRun`: reserved product language for a future agent execution tracked inside a terminal or another workspace tab. It is not a current storage model.
- `Design system`: the shared, presentational widget library in `lib/src/design_system/`, prefixed `Alera`, with co-located widget previews. See `docs/ui-styleguide.md`.

## Naming Rules

- Use `WorkspaceTabRecord`, `WorkspaceTabService`, and `WorkspaceTabKind` for persisted tabs.
- Use `TerminalSessionHandle`, `TerminalRuntime`, and `TerminalSurface` only for terminal execution/rendering.
- Keep `Workbench` for layout and interaction shell concepts, not for persisted tab records.
- Avoid introducing `TerminalTab` as a domain model. A terminal tab is currently a `WorkspaceTabRecord` with `kind == WorkspaceTabKind.terminal`.
- Avoid using `Workspace` and `Worktree` interchangeably. A workspace is product state; a worktree is a Git checkout implementation detail.

## Persistence

Alera persists projects, workspaces, workspace tabs, workbench layouts, settings, and view preferences in the Drift/SQLite schema defined in `lib/src/shared/infra/storage/drift_database.dart`.

Terminal workspace tabs store their durable `terminalSessionId` in the tab `payloadJson`. The terminal host stores runtime socket metadata and terminal checkpoints under the application support directory, outside Drift, so app/window close can detach from PTYs without killing running commands.

Legacy pre-Drift stores are no longer read or migrated.

## CLI Sidecar

Alera ships a separate Dart CLI named `alera` for non-UI background work. The desktop app launches `alera terminal-host` as a detached sidecar process instead of relaunching the Flutter app executable, so closing the app window detaches from terminal PTYs without creating another dock/taskbar app instance.

The CLI entrypoint is `bin/alera.dart` and uses `CommandRunner` from `package:args`. Release and desktop builds compile it with `dart build cli --target bin/alera.dart`, which preserves Dart build hooks and bundles the native assets required by dependencies such as `portable_pty`. The built CLI bundle is copied into `Contents/Resources/alera/` on macOS and `resources/alera/` next to the app executable on Linux and Windows.

The app resolves the sidecar through `AleraCliResolver`. Development builds may also use `.dart_tool/alera/bundle/bin/alera` or fall back to `dart run bin/alera.dart` when no compiled sidecar is present.

The shell eagerly starts the terminal host after the local database is available, before the first terminal tab is created. The app passes the current host lifecycle and host scrollback settings when launching `alera terminal-host`, then sends a `configure` request whenever terminal settings change so an already-running host updates without requiring an app restart.

The host stays alive only while it is useful. When all app clients disconnect and no PTYs are running, it stops after the configured empty-host delay, which defaults to 30 seconds. When app clients disconnect while PTYs are still running, it keeps those detached sessions alive for the configured detached-session delay, which defaults to one hour; if the app does not reconnect in time, the host terminates the PTYs and writes final checkpoints before exiting. On exit, the host removes its `host.json` control file so the next app launch cannot attach to stale socket metadata.

Host-side scrollback is bounded separately from the xterm row scrollback used for rendering. Each terminal session keeps a byte-limited chunk buffer, defaulting to 10 MB per session, and checkpoints that buffer about every five seconds plus immediately on detach, exit, configuration trimming, and host shutdown. This keeps detached-session resume useful without allowing terminal output to grow memory without bound.

## Agent Hook Status

Alera can show local Codex, Claude Code, GitHub Copilot, Antigravity, OpenCode, Pi, and Amp status for terminal workspace tabs when the user enables that agent's hook toggle in Settings. Each toggle is default-off because enabling it writes managed hook entries or managed status files into the user's agent config area. Codex, Claude Code, GitHub Copilot, and Antigravity write managed hook entries into `~/.codex/hooks.json`, `~/.claude/settings.json`, `~/.copilot/hooks/alera.json`, and `~/.gemini/config/hooks.json` for the `agy` CLI, plus fail-open scripts under `~/.alera/agent-hooks/`. OpenCode, Pi, and Amp write global managed files to `~/.config/opencode/plugins/alera-agent-status.js`, `~/.pi/agent/extensions/alera-agent-status.ts`, and `~/.config/amp/plugins/alera-agent-status.ts` respectively; `OPENCODE_CONFIG_DIR`, `PI_CODING_AGENT_DIR`, and `AMP_CONFIG_DIR` are honored when present. Disabling an agent removes only Alera-managed hook entries or files and preserves user-authored hooks/files.

The hook receiver runs in the Flutter app process, not in `alera terminal-host`. It uses `package:shelf` with `package:shelf_router` on top of a `dart:io` loopback HTTP server bound to `127.0.0.1:0`, writes the live port/token to `agent-hooks/endpoint.env` or `agent-hooks/endpoint.cmd` under the application support directory, and accepts `POST /hook/codex`, `POST /hook/claude`, `POST /hook/copilot`, `POST /hook/agy`, `POST /hook/opencode`, `POST /hook/pi`, and `POST /hook/amp` with `X-Alera-Agent-Hook-Token`. Terminal launches inject fresh `ALERA_AGENT_HOOK_*` values plus `ALERA_TERMINAL_SESSION_ID`, `ALERA_WORKSPACE_ID`, and `ALERA_TAB_ID`, after stripping any inherited Alera hook metadata from the shell environment. Receiver events for disabled agents return `204` without updating in-memory status, which prevents stale long-lived PTYs from reviving a disabled integration.

Managed hook scripts and managed status files read the endpoint file on every invocation/event before posting. This lets a PTY that survived an Alera restart report to the newly opened app receiver once the app is running again. Events emitted while the app is closed are intentionally missed because the receiver is app-local and the terminal host does not buffer hook events. OpenCode, Pi, and Amp are global integrations for now; they no-op outside Alera because the required `ALERA_TERMINAL_SESSION_ID`, `ALERA_WORKSPACE_ID`, and `ALERA_TAB_ID` metadata is absent. Local per-workspace overlays remain future work.

Agent status is in memory only. `AgentStatusController` stores the latest normalized status by `terminalSessionId`; after an app restart, each terminal tab starts as unknown until a supported agent emits another hook event. PTY exit may mark an active in-memory status as inferred `done`, but silence or elapsed time does not imply completion. Antigravity support uses Alera's technical agent id `agy`; OpenCode uses `opencode`; Pi uses `pi`; Amp uses `amp`.

Alera can also show native desktop notifications for agent status when the user enables **Agent status notifications** in Settings. Notifications are default-off, require at least one agent hook toggle to be enabled, and are emitted only while the Flutter app process is running. v1 notifies for `waiting`, `blocked`, and `done`; `working` updates stay in the in-app status projection. Notification payloads include the terminal session, workspace, tab, agent type, and state so selecting the notification can foreground the app, select the matching workspace, activate the matching workspace tab, and request terminal focus. If the app is closed when a hook event occurs, no notification is buffered or replayed on next launch.
