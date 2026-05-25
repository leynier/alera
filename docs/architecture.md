# Architecture

This document records the current product and code naming used by Alera. It is intentionally short and should stay aligned with implemented behavior.

## Naming Glossary

- `Project`: a local project path registered in Alera. It can be an existing local folder or a Git repository cloned from a URL; only Git-backed projects support linked workspaces.
- `Workspace`: a working context inside a project. A workspace points at one filesystem path and may point at one Git branch. The primary workspace points at the registered project path; linked workspaces point at Git worktrees and exist only for Git-backed projects.
- `Worktree`: the Git mechanism used to create an isolated checkout for a linked workspace. Use this term only for Git/filesystem behavior, not for the Alera UI container. Folder-only projects do not use worktrees.
- `Workbench`: the main interactive area for an active workspace. It owns pane layout, active group selection, and workspace tabs. A project may be active while no workspace is selected; in that state the shell shows an empty workspace surface and workspace-scoped panels should render without workspace context.
- `WorkbenchPaneGroup`: one pane in the split layout. It contains an ordered list of workspace tab ids and one active tab id.
- `WorkspaceTab`: the domain concept for a tab inside a workspace. It is intentionally broader than terminal because future tabs may represent editors, browsers, previews, or other surfaces.
- `TerminalSession`: the runtime process/PTY state attached to a terminal workspace tab. It is not the persisted tab record.
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

Legacy pre-Drift stores are no longer read or migrated.
