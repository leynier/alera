# Feature Matrix

Status meanings: `Real` uses production Alera boundaries and live state, `Partial` proves the core path but lacks daily-driver UX or edge cases, `Excluded` was explicitly outside this POC.

Audit note (2026-08-24): this matrix describes implementation scope and runtime boundaries. It does not by itself prove visual or interaction parity. The live status, evidence and remaining gaps are tracked in `/Volumes/ExternalStorage/Projects/alera/todo.md`; a row remains `parcial` there until Flutter and GPUI are compared across the relevant states.

| Area | Status | Implemented | Remaining Before Daily Use |
| --- | --- | --- | --- |
| GPUI shell | Real | Flutter-aligned dark shell, welcome dashboard, activity navigation, project/workspace sidebar, tabs, status and connection state, native app menu and keyboard actions | Packaging and cross-platform release audit |
| Runtime coexistence | Real | Shared protocol/client, authenticated host connection, binary frames, notifications, reconnect and simultaneous Flutter/GPUI clients | Packaging and compatibility matrix across released host versions |
| Projects and workspaces | Real | Live lists and selection, local registration, repository clone with progress polling, managed workspace creation, branch, pinned state, tags, relations, menus and tabs | Packaging and cross-platform release audit |
| Workbench layout | Real | Layout rendering/persistence, split panes, resize, indexed tab reorder, cross-pane drag/drop, directional split previews, empty-pane pruning, active-group restoration and close/create tab UX | Packaging and cross-platform release audit |
| Terminal core | Real | Real PTY attach, snapshot, binary output, keyboard input, bracketed paste, resize, title, scrollback and detach | None for the validated core data path |
| Terminal daily-driver behavior | Real | ANSI styles, Unicode cells, control responses, output resync, selection/copy, bracketed paste, IME-safe input, hyperlinks, path drop, cursor controls, recovery and split terminals | LSP and advanced Kitty graphics remain excluded |
| Explorer | Real | Safe canonical paths, lazy directory expansion, text/image opening, create/rename/delete/move, source-control roots, polling refresh and off-thread I/O | Drag/drop and richer metadata |
| Search and replace | Real | Workspace search, clickable grouped results, regex/case/whole-word/ignored/include/exclude toggles and confirmed replace-all | Packaging and cross-platform release audit |
| Editor | Real | Multiline code editor, Tree-sitter highlighting, dirty state, safe write, external conflict confirmation, preview/source toolbar and editor tabs | LSP remains excluded |
| Markdown preview | Real | Native Markdown rendering with source/preview toggle | Link routing and full style parity |
| Mermaid preview | Real | In-process SVG generation, themed SVG display, contained viewport, zoom and pan | Diagnostic details, link routing and very-large-document policy |
| Image preview | Real | Safe local raster/SVG resolution, contained viewport, zoom, pan and bounded drag | Metadata and very-large-image policy |
| Git status and diff | Real | Status, staged/unstaged files, current branch, diff, history, tree/list modes and conflict editor | Packaging and cross-platform release audit |
| Git mutations | Real | Stage/unstage/discard all or path, commit/amend, fetch, pull, push, stash and pop | Dedicated credential/error remediation and granular hunk staging |
| Pull requests and CI | Real | GitHub authentication state, current-branch PR, checks, comments/reviews, create/update, ready/draft, comment, close and merge methods | GitLab/Azure providers and browser links remain excluded |
| AI Text | Real | Existing workspace-identity agent, 10 minute deadline, output, cancellation, retry and workspace continuation | Packaging and cross-platform release audit |
| Agents, profiles and quotas | Real | Live profiles, typed profile editor, quotas and presence plus allowlisted runtime mutations and hook controls | Packaging and cross-platform release audit |
| Resource Manager | Real | Live process snapshot, hierarchy, sorting, polling and confirmed terminate/restart calls with normalized CPU presentation | Graph history remains out of scope |
| Orchestration | Real | Live runs, tasks, gates and terminals plus protocol-v2 verbs, typed run-policy controls and confirmations | Packaging and cross-platform release audit |
| Settings | Real | Runtime, workbench, provider, AI Text, editor, terminal, keyboard, project, mobile and profile settings with scoped updates, validation and search | Packaging and cross-platform release audit |
| Mobile devices | Real | Local status, devices, runtime settings, pairing, cancellation, rename, revoke/delete and non-cloud mobile verbs | Emulator embedding remains excluded |
| Diagnostics | Real | Runtime/CLI status, CLI registration, shell environment reload, log viewer/open-folder and diagnostics bundle export | Packaging and cross-platform release audit |
| Browser | Excluded | None | Explicitly deferred |
| Updater | Excluded | None | Explicitly deferred |
| PDF preview | Excluded | None | Explicitly deferred |
| Emulator embedding | Excluded | None | Explicitly deferred |
| Account and OAuth | Excluded | None | Explicitly deferred |
| SSH | Excluded | None | Explicitly deferred |
| LSP | Excluded | None | Explicitly deferred |
| Platform validation | Partial | macOS debug bundle, native folder picker, window zoom behavior and Flutter/GPUI coexistence verified in a live desktop session | Windows and Linux packaging plus platform-specific interaction validation |

## Interpretation

The architecture and real core workflows are feasible. The GPUI app now has practical visual parity with the Flutter shell and validated primary project, workspace, terminal, explorer, search, Git, forge, AI and runtime surfaces. Broad administrative areas remain operational through live cards and safe JSON consoles, while the partial and excluded rows above still require dedicated product work before GPUI can replace every Flutter capability.
