# Alera Roadmap

Comprehensive feature roadmap for Alera. Each feature is scored on two axes:

- **Difficulty** (1–5): estimated implementation effort (1 = trivial, 5 = very complex)
- **Utility** (1–5): how useful or frequently used the feature is in an app of this type (1 = niche, 5 = essential)

### Status legend

| Status | Meaning |
|---|---|
| **Shipped** | Core behavior is implemented and usable |
| **Partial** | Meaningful foundation exists, but the roadmap description is not fully met |
| **Planned** | Not meaningfully implemented yet |

---

## Agent Integration

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Agent auto-detection & registry | 3 | 5 | Partial | Fixed registry of supported agents (`AgentType`) with managed hooks, icons, and user-declared managed/command profiles; arbitrary CLI install detection and selection UI are still unavailable |
| Agent status tracking | 3 | 5 | Shipped | Real-time idle/active/waiting/blocked/done state with visual dots per worktree |
| Agent lifecycle hooks | 4 | 4 | Shipped | Fire hooks when agents start/stop; relay for inter-process communication |
| Agent awake service | 2 | 3 | Shipped | Prevent system sleep while agents work (caffeinate / lid-sleep) |
| Managed agent profiles & trust controls | 2 | 3 | Shipped | User-declared profiles with adapter-specific model, permission, sandbox, trust, clone, default, and command-preview controls; command mode remains for advanced or unsupported options |
| Agent interrupt intent | 2 | 4 | Partial | Interrupted runs are detected and surfaced in status; no first-class graceful interrupt protocol/API yet |
| Orchestration between agents | 5 | 5 | Shipped | Inter-agent messaging with push-on-idle delivery, task DAG, dispatch with circuit breaker, decision gates, coordinator loop (`alera orchestration`) |

---

## Terminal

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Terminal search | 2 | 5 | Shipped | Literal, case-insensitive search across bounded scrollback with match navigation and `Mod+F` |
| Terminal session persistence | 4 | 4 | Shipped | Runtime host checkpoints, bounded scrollback restore, PTY detach across app restart; live processes survive host lifecycle |
| Terminal quick commands | 2 | 3 | Planned | Shortcut palette for frequently used terminal commands (mobile Terminal Quick Keys are local accessories, not this feature) |
| Floating terminal panel | 3 | 3 | Planned | Floating, resizable terminal overlay with window controls |
| Terminal ligatures | 2 | 2 | Planned | Font ligature support in terminal rendering |
| Ghostty settings import | 2 | 2 | Planned | Import terminal settings from Ghostty config files |
| Terminal stream protocol | 4 | 3 | Shipped | Mobile companion streams terminal I/O over the runtime WebSocket gateway; desktop uses the host socket protocol |
| Tab cycling & reopen closed tab | 2 | 4 | Partial | Next/previous tab and go-to-tab 1–9 shortcuts ship; browser tabs can reopen the 10 most recent closed pages, while general workspace-tab reopen remains |

---

## Editor & Files

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| File Explorer panel | 4 | 5 | Shipped | Tree-based file browser with virtual rows, git-ignored toggle, inline rename |
| Code edition with LSP support | 5 | 5 | Partial | In-app editor via `code_forge` with syntax themes, find, undo/redo, save/dirty state; no language server protocol yet |
| Markdown editor | 4 | 3 | Planned | WYSIWYG markdown editing with toolbar, slash menu, code blocks, tables, mermaid |
| Markdown viewer | 2 | 3 | Shipped | View rendered markdown files in workspace tabs |
| Open in with other softwares | 2 | 4 | Partial | Open workspace/folder in OS file manager (Linux selects via FileManager1.ShowItems with parent-folder fallback) and open repository in browser; no VS Code / Cursor / Zed / custom editor launcher yet |
| Autosave | 2 | 4 | Planned | Automatic file saving with configurable behavior |
| Editor scroll restore | 1 | 3 | Planned | Persist and restore scroll position across sessions |
| External file watch | 2 | 4 | Partial | Explorer and source-control file watches are live; editor reloads/conflicts on external disk changes; no full prompt-to-reload product surface yet |
| PDF viewer | 3 | 2 | Shipped | Render PDFs with inline tabs and in-document search |
| CSV viewer | 2 | 2 | Planned | Tabular display for CSV/TSV data |
| Jupyter Notebook viewer | 3 | 2 | Planned | Render `.ipynb` files with cell outputs |
| Image viewer | 2 | 3 | Shipped | Image display with secure preview, zoom, and pan controls |
| Mermaid viewer | 2 | 2 | Shipped | Standalone rendered mermaid diagram viewer in tabs |

---

## Search

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Search panel | 3 | 5 | Shipped | Text search and replace across workspace files with include/exclude patterns |

---

## Source Control & Diffs

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Diff panel | 4 | 5 | Shipped | Unified diff view with file tree navigation |
| Diffs per file | 3 | 5 | Shipped | File-level diff view with line stats |
| Diffs global | 3 | 4 | Shipped | Aggregated diff across all changed files |
| Git status with operations | 4 | 5 | Shipped | Staging, commit, pull, push, discard with full UI |
| Submodule inspection | 3 | 4 | Shipped | Lazy one-level read-only status and diffs; parent actions remain scoped to changed gitlinks |
| Commit and PR messages with AI | 3 | 4 | Shipped | AI-generated commit messages and pull request titles/descriptions |
| Conflict view and resolver | 4 | 4 | Planned | Conflicts are detected and block some git ops; no visual merge resolver UI yet |
| Conflict resolution with AI | 4 | 3 | Planned | AI-assisted three-way merge conflict resolution |
| Git history panel with graph | 4 | 4 | Shipped | Collapsible Source Control commits section with HEAD/upstream graph and commit diff tabs |
| Diff annotations & inline comments | 4 | 3 | Planned | Comment threads on diff lines with popovers |
| Send diff annotations to agent | 3 | 4 | Planned | Send annotated diffs directly to agents for action |
| Image diff | 3 | 2 | Shipped | Side-by-side before/after image comparison for binary diffs |

---

## Integrations & Providers

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Pull requests panel | 4 | 4 | Shipped | Create, edit, comment (markdown), toggle draft, and merge reviews per worktree on GitHub, GitLab, and Azure DevOps |
| Checks panel (CI/CD) | 4 | 4 | Shipped | CI checks grouped by status with drill-down details on GitHub, GitLab, and Azure DevOps |
| GitHub Projects integration | 4 | 3 | Planned | Full project board with columns, cards, filtering, inline editing |
| Linear integration | 4 | 2 | Planned | Linear SDK, issue workspace, item drawer, team selection |
| Alera account identity | 4 | 4 | Shipped | Optional Google and GitHub sign-in, linked verified identities, rotating Alera sessions, runtime ownership, mobile enrollment, and account deletion |
| Multi-account support | 3 | 3 | Partial | Mobile retains multiple Alera account sessions; desktop provider-account switching and multiple simultaneous runtime identities are not implemented |

---

## Browser

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Browser tab | 4 | 4 | Shipped | Persisted native browser tabs using WKWebView, WebView2, or WebKitGTK; Alera does not bundle Chromium or CEF |
| Browser Use | 5 | 4 | Shipped | App-routed automation with snapshots, refs, click, fill, type, select, focus, hover, scroll, wait, local eval, screenshots, and PDF export |
| Browser session profiles | 3 | 3 | Partial | Create, delete, switch, isolated storage, and atomic cookie import are shipped; profile cloning is not |

---

## Workspace & Navigation

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Quick Open / Command Palette | 3 | 5 | Planned | Fuzzy file search (Cmd+P) and command execution (Cmd+Shift+P) |
| Worktree navigation history | 2 | 4 | Shipped | Back/forward navigation stack between worktrees |
| Worktree sleep/wake | 3 | 3 | Shipped | Sleep removes tabs/layout and terminates terminals while keeping branch/files; desktop and mobile |
| Worktree comments & metadata | 2 | 3 | Partial | Rename, pins, tags, and parent/child relations ship; freeform comments and issue links do not |
| Worktree multi-selection | 2 | 3 | Planned | Select multiple worktrees for batch operations |
| Worktree manual ordering | 2 | 3 | Planned | Sort by name/recent/activity exists; no drag-and-drop manual order with persistence |
| Smart workspace naming | 2 | 3 | Planned | Manual name field on create; no intelligent auto-naming suggestions yet |
| Prompt-driven workspace creation | 4 | 4 | Shipped | Create a managed workspace from a prompt with project, branch, parent workspace, agent profile, and deferred setup preserved across desktop and mobile |
| Workspace cleanup dialog | 2 | 3 | Planned | Bulk cleanup of stale worktrees |
| Status bar | 2 | 4 | Partial | Agent quota and Resource Manager status-bar controls ship; general SSH/ports/disk status remains unavailable |
| UI zoom controls | 1 | 3 | Planned | Zoom in/out/reset for the entire UI |
| Global file drop | 2 | 3 | Partial | Terminal OS drop pastes absolute paths; explorer/editor/composer drops still planned |

---

## Kanban & Task Management

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Kanban panel | 3 | 3 | Planned | Kanban board with status lanes, cards, drag-drop |

---

## Automations

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Automations system | 4 | 4 | Planned | Cron-style scheduled agent workflows with templates and run history |

---

## Activity & Notifications

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Activity feed | 3 | 5 | Partial | Agent activity sort, sidebar agent runs, and status projection ship; no unified chronological activity feed yet |
| Notification system | 3 | 4 | Partial | Native desktop notifications plus opt-in FCM mobile push for attention, done, orchestration, and terminal-exit events with tap routing; no unread model or OS dock badge yet |
| Agent auto-acknowledge | 1 | 3 | Shipped | Viewing a completed agent tab acknowledges that completion epoch and clears attention until the next run |

---

## Usage & Analytics

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Agent quota status bar | 3 | 4 | Shipped | Bottom status bar with local/remote quota usage for Claude Code and CCS profiles, Codex, Kimi, Grok Build, Cursor, Antigravity, MiniMax, and Z.ai |
| Per-agent usage charts | 3 | 4 | Planned | Daily usage visualization per agent provider |
| Cost tracking | 3 | 4 | Planned | API cost monitoring and visualization |
| Share/export usage | 2 | 2 | Planned | Export or share usage stats |

---

## Resource & System Management

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Resource manage | 3 | 3 | Shipped | Status-bar Resource Manager: per-session CPU/memory attributed to Project -> Workspace -> Tab, orphan session detection and kill, host memory and load; local host only |
| Space analyzer | 2 | 3 | Planned | Disk space tracking and compaction per workspace |
| Port scanning & dev server management | 3 | 4 | Planned | Auto-detect open ports, panel listing active dev servers |

---

## Remote & Mobile

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| SSH | 5 | 4 | Partial | SSH targets, signed remote runtime bootstrap, Settings → Remote Hosts, `alera ssh-target`, and host-aware workspace metadata; full remote PTY/filesystem/git worktrees as local are not complete |
| Computer Use | 5 | 3 | Partial | `alera computer` reads and drives application windows through AT-SPI, UI Automation, or AXUIElement on Linux, Windows, and macOS; synthetic input and screen capture are not offered yet |
| Mobile emulator tabs | 5 | 4 | Shipped | Workspace tabs for Android emulators and iOS simulators with capability-gated streaming, observation, input, install/launch, and platform-specific diagnostics; availability depends on the host SDK/backend |
| Mobile App | 5 | 3 | Shipped | Pairing and terminal foundation plus sidebar parity, secure multi-account enrollment, FCM receipt and tap routing, settings/hooks/quotas, and managed workspace actions; richer non-terminal tab surfaces planned |

---

## CLI

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Alera CLI | 4 | 4 | Shipped | Rust `alera` sidecar: `runtime`, `project`, `workspace`, `tag`, `tab`, `terminal`, `ssh-target`, `mobile`, `computer`, `browser`, `emulator`, and `orchestration`; automations remain future |

---

## Settings & Customization

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Customizable keyboard shortcuts | 3 | 4 | Shipped | Settings pane to remap chords with conflict detection and reset; no separate file import/export yet |
| Skills system | 3 | 3 | Partial | Install/update Alera CLI and orchestration skills from Settings; no general browse/manage agent skills marketplace |
| MCP configuration management | 3 | 3 | Planned | Manage Model Context Protocol server configurations |
| Project configuration file (alera.toml) | 3 | 4 | Shipped | Per-repo `alera.toml` (and Settings UI overrides) for worktree copy/setup and git hosting provider; sparse checkout presets not in v1 |

---

## Onboarding & Discovery

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Onboarding wizard | 3 | 4 | Planned | Multi-step first-run setup for agents, repos, theme, integrations |
| Feature tips & discovery | 2 | 3 | Planned | Contextual hints for undiscovered features |

---

## Voice

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Voice / dictation / STT | 4 | 2 | Planned | Offline speech-to-text via sherpa-onnx, dictation controller, voice settings |

---

## Telemetry & Diagnostics

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Telemetry & analytics | 3 | 3 | Planned | Usage analytics with consent management |
| Crash reporting | 2 | 3 | Shipped | Opt-in Sentry reporting for desktop, mobile, and runtime; disabled by default and controlled from diagnostics settings |
| Diagnostic bundles | 2 | 2 | Shipped | Export app and runtime logs plus version metadata as a redacted ZIP; mobile exports logs through the share sheet |
| Privacy settings | 2 | 3 | Partial | Crash-reporting consent exists; general telemetry opt-in/out controls remain to be implemented |

---

## Score Summary

### Top features by Utility (5/5)

| Feature | Difficulty | Status |
|---|:---:|:---:|
| Agent auto-detection & registry | 3 | Partial |
| Agent status tracking | 3 | Shipped |
| Terminal search | 2 | Shipped |
| File Explorer panel | 4 | Shipped |
| Code edition with LSP support | 5 | Partial |
| Search panel | 3 | Shipped |
| Diff panel | 4 | Shipped |
| Diffs per file | 3 | Shipped |
| Git status with operations | 4 | Shipped |
| Orchestration between agents | 5 | Shipped |
| Quick Open / Command Palette | 3 | Planned |
| Activity feed | 3 | Partial |

### Lowest difficulty with high utility (Difficulty ≤ 2, Utility ≥ 4)

| Feature | Difficulty | Utility | Status |
|---|:---:|:---:|:---:|
| Terminal search | 2 | 5 | Shipped |
| Open in with other softwares | 2 | 4 | Partial |
| Tab cycling & reopen closed tab | 2 | 4 | Partial |
| Autosave | 2 | 4 | Shipped |
| Worktree navigation history | 2 | 4 | Shipped |
| Status bar | 2 | 4 | Partial |

### Recently reconciled from code audit (2026-08-01)

Features whose status or scope was checked against the current implementation:

| Feature | Current status |
|---|:---:|
| Terminal session persistence | Shipped |
| Terminal stream protocol | Shipped |
| Image diff | Shipped |
| Worktree sleep/wake | Shipped |
| Alera CLI | Shipped |
| Customizable keyboard shortcuts | Shipped |
| Project configuration file | Shipped |
| Agent auto-acknowledge | Shipped |
| Code edition (without LSP) | Partial |
| SSH targets/bootstrap | Partial |
| Notification system | Partial |
| Skills install controls | Partial |
| Worktree metadata (rename/tags/pins) | Partial |
| Tab cycling (browser reopen; general reopen pending) | Partial |
| Open in file manager / browser | Partial |
| External file watch foundation | Partial |
| Activity projection (not full feed) | Partial |
| Status bar (quota and Resource Manager) | Partial |
| Agent registry (fixed set) | Partial |
| Agent interrupt detection | Partial |
| Managed agent profiles and trust controls | Shipped |
| Browser tab | Shipped |
| Browser Use | Shipped |
| Browser session profiles | Partial |
| Computer Use | Partial |
| Mobile emulator tabs | Shipped |
| Prompt-driven workspace creation | Shipped |
| Crash reporting | Shipped |
| Diagnostic bundles | Shipped |
| Privacy settings | Partial |
