# Architecture

This document records the current product and code naming used by Alera. It is intentionally short and should stay aligned with implemented behavior.

## Naming Glossary

- `Project`: a local Git repository registered in Alera.
- `Workspace`: a working context inside a project. A workspace usually points at one filesystem path and one Git branch. The main workspace points at the original repository checkout; linked workspaces point at Git worktrees.
- `Worktree`: the Git mechanism used to create an isolated checkout for a linked workspace. Use this term only for Git/filesystem behavior, not for the Alera UI container.
- `Workbench`: the main interactive area for an active workspace. It owns pane layout, active group selection, and workspace tabs.
- `WorkbenchPaneGroup`: one pane in the split layout. It contains an ordered list of workspace tab ids and one active tab id.
- `WorkspaceTab`: the domain concept for a tab inside a workspace. It is intentionally broader than terminal because future tabs may represent editors, browsers, previews, or other surfaces.
- `TerminalSession`: the runtime process/PTY state attached to a terminal workspace tab. It is not the persisted tab record.
- `SidebarTerminalTabRow`: the sidebar projection for terminal workspace tabs. The sidebar does not render every workspace tab type by default.
- `AgentRun`: reserved product language for a future agent execution tracked inside a terminal or another workspace tab. It is not a current storage model.

## Naming Rules

- Use `WorkspaceTabRecord`, `WorkspaceTabService`, and `WorkspaceTabKind` for persisted tabs.
- Use `TerminalSessionHandle`, `TerminalRuntime`, and `TerminalSurface` only for terminal execution/rendering.
- Keep `Workbench` for layout and interaction shell concepts, not for persisted tab records.
- Avoid introducing `TerminalTab` as a domain model. A terminal tab is currently a `WorkspaceTabRecord` with `kind == WorkspaceTabKind.terminal`.
- Avoid using `Workspace` and `Worktree` interchangeably. A workspace is product state; a worktree is a Git checkout implementation detail.

## Persistence Compatibility

The current workspace tab store remains named `workbench_tabs` on disk so existing local Sembast databases continue to load. The code-level store alias is `AleraStores.workspaceTabs`.

Older builds used `terminal_tabs`. That store is treated as legacy migration input and cleanup data only through `AleraStores.legacyTerminalTabs`.
