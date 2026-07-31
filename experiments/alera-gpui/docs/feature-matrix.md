# Feature Matrix

Status meanings: `Real` uses production Alera boundaries and live state, `Partial` proves the core path but lacks daily-driver UX or edge cases, `Excluded` was explicitly outside this POC.

| Area | Status | Implemented | Remaining Before Daily Use |
| --- | --- | --- | --- |
| GPUI shell | Real | Dark Alera shell, activity rail, project/workspace sidebar, tabs, status and connection state | Accessibility labels, complete keyboard registry, menus, window state and visual polish |
| Runtime coexistence | Real | Shared protocol/client, authenticated host connection, binary frames, notifications, reconnect and simultaneous Flutter/GPUI clients | Packaging and compatibility matrix across released host versions |
| Projects and workspaces | Partial | Live project/workspace lists, selection, branch, pinned state and tabs | Create, rename, remove, pin/tag/link and setup flows need dedicated GPUI controls |
| Workbench layout | Partial | Layout is loaded and tabs follow runtime state | Split panes, layout rendering/persistence, drag/drop and close/create tab UX |
| Terminal core | Real | Real PTY attach, snapshot, binary output, keyboard input, bracketed paste, resize, title, scrollback and detach | None for the validated core data path |
| Terminal daily-driver behavior | Partial | ANSI styles, Unicode cells, control responses and output resync | Selection/copy, IME, mouse reporting, hyperlinks, search, focus reporting, Kitty keyboard/graphics and split terminals |
| Explorer | Real | Safe canonical paths, lazy directory expansion, text/image opening and off-thread I/O | Create, rename, delete, drag/drop, file watching and richer metadata |
| Search and replace | Partial | Workspace search, clickable results and confirmed replace-all | UI toggles for regex, case, whole word, ignored files and include/exclude patterns |
| Editor | Partial | Multiline code editor, Tree-sitter highlighting, dirty state, safe write and overwrite confirmation | Multiple editor tabs, undo persistence, find, command integration, large-file virtualization and richer language behavior; LSP is excluded |
| Markdown preview | Real | Native Markdown rendering with source/preview toggle | Link routing and full style parity |
| Mermaid preview | Real | In-process SVG generation and GPUI display | Interactive pan/zoom and diagnostic details |
| Image preview | Real | Safe local raster/SVG resolution and rendering | Zoom, pan, metadata and very-large-image policy |
| Git status and diff | Real | Status, staged/unstaged files, current branch, diff and history | Side-by-side/hunk UI and conflict editor |
| Git mutations | Real | Stage/unstage/discard all or path, commit/amend, fetch, pull, push, stash and pop | Dedicated credential/error remediation and granular hunk staging |
| Pull requests and CI | Partial | GitHub authentication state, current-branch PR, checks, comments/reviews, create/update, ready/draft, comment, close and merge methods | GitLab/Azure providers, review-thread resolution, richer check logs and browser links |
| AI Text | Real | Existing workspace-identity agent, 10 minute deadline, output and cancel | Purpose-built result editing/apply UX |
| Agents, profiles and quotas | Partial | Live profiles, quotas and presence plus allowlisted runtime mutations | Typed forms, validation hints, hook editor and task-specific result rendering |
| Resource Manager | Partial | Live process snapshot and confirmed terminate/restart calls | Tables, sorting, polling policy, graphs and normalized CPU presentation |
| Orchestration | Partial | Live runs, tasks, gates and terminals plus all protocol-v2 verbs through an allowlist | DAG visualization, decision-gate forms, threaded messages and recovery UX |
| Settings | Partial | Runtime, workbench and effective project settings plus scoped updates | Typed settings screens, defaults, validation and search |
| Mobile devices | Partial | Local status, devices and runtime settings plus non-cloud, non-emulator mobile verbs | Typed pairing/device management screens and platform-specific guidance |
| Diagnostics | Partial | Runtime/CLI status, CLI registration and shell environment reload | Bundle collection, log viewer, copy/report actions and tailored remediation |
| Browser | Excluded | None | Explicitly deferred |
| Updater | Excluded | None | Explicitly deferred |
| PDF preview | Excluded | None | Explicitly deferred |
| Emulator embedding | Excluded | None | Explicitly deferred |
| Account and OAuth | Excluded | None | Explicitly deferred |
| SSH | Excluded | None | Explicitly deferred |
| LSP | Excluded | None | Explicitly deferred |
| macOS and Windows | Excluded | None | A production migration must design and verify both |

## Interpretation

The architecture and real core workflows are feasible. The POC is intentionally not a drop-in daily driver: broad administrative areas are operational through live cards and safe JSON consoles, while terminal interaction, workbench layout, provider coverage and product-grade forms still require a dedicated implementation phase.
