# Alera Roadmap

Comprehensive feature roadmap for Alera. Each feature is scored on two axes:

- **Difficulty** (1–5): estimated implementation effort (1 = trivial, 5 = very complex)
- **Utility** (1–5): how useful or frequently used the feature is in an app of this type (1 = niche, 5 = essential)

---

## Agent Integration

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Agent auto-detection & registry | 3 | 5 | Planned | Detect installed CLI agents (Claude Code, Codex, Gemini, etc.) and expose a selection UI |
| Agent status tracking | 3 | 5 | Shipped | Real-time idle/active/waiting state with visual dots per worktree |
| Agent lifecycle hooks | 4 | 4 | Shipped | Fire hooks when agents start/stop; relay for inter-process communication |
| Agent awake service | 2 | 3 | Shipped | Prevent system sleep while agents work (caffeinate / lid-sleep) |
| Agent trust presets | 2 | 3 | Planned | Per-agent permission and trust configuration |
| Agent interrupt intent | 2 | 4 | Planned | Graceful agent interruption protocol |
| Orchestration between agents | 5 | 5 | Shipped | Inter-agent messaging with push-on-idle delivery, task DAG, dispatch with circuit breaker, decision gates, coordinator loop (`alera orchestration`) |

---

## Terminal

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Terminal search | 2 | 5 | Planned | In-terminal text search across scrollback |
| Terminal session persistence | 4 | 4 | Planned | Save/restore terminal buffers across app restart (not just tab records) |
| Terminal quick commands | 2 | 3 | Planned | Shortcut palette for frequently used terminal commands |
| Floating terminal panel | 3 | 3 | Planned | Floating, resizable terminal overlay with window controls |
| Terminal ligatures | 2 | 2 | Planned | Font ligature support in terminal rendering |
| Ghostty settings import | 2 | 2 | Planned | Import terminal settings from Ghostty config files |
| Terminal stream protocol | 4 | 3 | Planned | Protocol for streaming terminal output to mobile/remote clients |
| Tab cycling & reopen closed tab | 2 | 4 | Planned | Cycle tabs by type/recent order; reopen recently closed tabs |

---

## Editor & Files

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| File Explorer panel | 4 | 5 | Shipped | Tree-based file browser with virtual rows, git-ignored toggle, inline rename |
| Code edition with LSP support | 5 | 5 | Planned | Full code editor with language server protocol integration |
| Markdown editor | 4 | 3 | Planned | WYSIWYG markdown editing with toolbar, slash menu, code blocks, tables, mermaid |
| Markdown viewer | 2 | 3 | Shipped | View rendered markdown files in workspace tabs |
| Open in with other softwares | 2 | 4 | Planned | Open files/folders in VS Code, Cursor, Zed, custom editors, file manager |
| Autosave | 2 | 4 | Planned | Automatic file saving with configurable behavior |
| Editor scroll restore | 1 | 3 | Planned | Persist and restore scroll position across sessions |
| External file watch | 2 | 4 | Planned | Detect external file changes and prompt reload |
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
| Conflict view and resolver | 4 | 4 | Planned | Visual conflict display with merge controls |
| Conflict resolution with AI | 4 | 3 | Planned | AI-assisted three-way merge conflict resolution |
| Git history panel with graph | 4 | 4 | Shipped | Collapsible Source Control commits section with HEAD/upstream graph and commit diff tabs |
| Diff annotations & inline comments | 4 | 3 | Planned | Comment threads on diff lines with popovers |
| Send diff annotations to agent | 3 | 4 | Planned | Send annotated diffs directly to agents for action |
| Image diff | 3 | 2 | Planned | Side-by-side image comparison for binary diffs |

---

## Integrations & Providers

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Pull requests panel | 4 | 4 | Shipped | Create, edit, comment (markdown), toggle draft, and merge PRs per worktree on GitHub and Azure DevOps |
| Checks panel (CI/CD) | 3 | 4 | Shipped | CI checks grouped by status with drill-down details on GitHub and Azure DevOps; GitLab planned |
| GitHub Projects integration | 4 | 3 | Planned | Full project board with columns, cards, filtering, inline editing |
| Linear integration | 4 | 2 | Planned | Linear SDK, issue workspace, item drawer, team selection |
| Multi-account support | 3 | 3 | Planned | Account switcher, manage multiple accounts per provider |

---

## Browser

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Browser tab | 4 | 4 | Planned | Embedded Chromium browser with address bar and navigation |
| Browser Use | 5 | 4 | Planned | Full browser automation: snapshot, click, fill, screenshot, eval, etc. |
| Browser session profiles | 3 | 3 | Planned | Create, clone, switch browser profiles with cookie import |

---

## Workspace & Navigation

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Quick Open / Command Palette | 3 | 5 | Planned | Fuzzy file search (Cmd+P) and command execution (Cmd+Shift+P) |
| Worktree navigation history | 2 | 4 | Planned | Back/forward navigation stack between worktrees |
| Worktree sleep/wake | 3 | 3 | Planned | Sleep worktrees to save resources; wake when needed |
| Worktree comments & metadata | 2 | 3 | Planned | Display names, comments, issue links on worktrees |
| Worktree multi-selection | 2 | 3 | Planned | Select multiple worktrees for batch operations |
| Worktree manual ordering | 2 | 3 | Planned | Drag-and-drop worktree reorder with persistence |
| Smart workspace naming | 2 | 3 | Planned | Intelligent auto-naming suggestions for new worktrees |
| Workspace cleanup dialog | 2 | 3 | Planned | Bulk cleanup of stale worktrees |
| Status bar | 2 | 4 | Planned | SSH status, ports, resources, update status, disk usage |
| UI zoom controls | 1 | 3 | Planned | Zoom in/out/reset for the entire UI |
| Global file drop | 2 | 3 | Planned | Drag files from OS into the app |

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
| Activity feed | 3 | 5 | Planned | Unified activity feed with agent completion tracking |
| Notification system | 3 | 4 | Planned | Agent notifications, unread tracking, OS dock badge |
| Agent auto-acknowledge | 1 | 3 | Planned | Mark viewed agent completions as read automatically |

---

## Usage & Analytics

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Agent quota status bar | 3 | 4 | Shipped | Bottom status bar with local/remote quota usage for Claude Code and CCS profiles, Codex, Kimi, Grok Build, Antigravity, MiniMax, and Z.ai |
| Per-agent usage charts | 3 | 4 | Planned | Daily usage visualization per agent provider |
| Cost tracking | 3 | 4 | Planned | API cost monitoring and visualization |
| Share/export usage | 2 | 2 | Planned | Export or share usage stats |

---

## Resource & System Management

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Resource manage | 3 | 3 | Planned | System resource consumption monitoring |
| Space analyzer | 2 | 3 | Planned | Disk space tracking and compaction per workspace |
| Port scanning & dev server management | 3 | 4 | Planned | Auto-detect open ports, panel listing active dev servers |

---

## Remote & Mobile

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| SSH | 5 | 4 | Planned | SSH targets, remote PTY, remote filesystem, remote git |
| Computer Use | 5 | 3 | Planned | Native desktop automation via Accessibility APIs |
| Mobile App | 5 | 3 | Shipped | Foundation: desktop pairing UI with QR in Settings → Mobile Devices, `alera mobile` CLI, secure device tokens, WebSocket gateway, project/workspace listing, hosted terminal attach; richer live transport planned |

---

## CLI

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Alera CLI | 4 | 4 | Planned | Full CLI: worktrees, terminals, repos, automations, orchestration, browser |

---

## Settings & Customization

| Feature | Difficulty | Utility | Status | Notes |
|---|:---:|:---:|:---:|---|
| Customizable keyboard shortcuts | 3 | 4 | Planned | File-based keybinding config with import/export and conflict detection |
| Skills system | 3 | 3 | Planned | Browse, manage, and configure agent skills |
| MCP configuration management | 3 | 3 | Planned | Manage Model Context Protocol server configurations |
| Project configuration file (alera.yaml) | 3 | 4 | Planned | Per-repo setup scripts, hooks, symlinks, sparse checkout presets |

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
| Crash reporting | 2 | 3 | Planned | Crash report dialog and collection |
| Diagnostic bundles | 2 | 2 | Planned | Collect diagnostic info for user support |
| Privacy settings | 2 | 3 | Planned | Opt-in/out controls for telemetry |

---

## Score Summary

### Top features by Utility (5/5)

| Feature | Difficulty | Status |
|---|:---:|:---:|
| Agent auto-detection & registry | 3 | Planned |
| Agent status tracking | 3 | Shipped |
| Terminal search | 2 | Planned |
| File Explorer panel | 4 | Shipped |
| Code edition with LSP support | 5 | Planned |
| Search panel | 3 | Shipped |
| Diff panel | 4 | Shipped |
| Diffs per file | 3 | Shipped |
| Git status with operations | 4 | Shipped |
| Orchestration between agents | 5 | Shipped |
| Quick Open / Command Palette | 3 | Planned |
| Activity feed | 3 | Planned |

### Lowest difficulty with high utility (Difficulty ≤ 2, Utility ≥ 4)

| Feature | Difficulty | Utility | Status |
|---|:---:|:---:|:---:|
| Terminal search | 2 | 5 | Planned |
| Open in with other softwares | 2 | 4 | Planned |
| Tab cycling & reopen closed tab | 2 | 4 | Planned |
| Autosave | 2 | 4 | Planned |
| Worktree navigation history | 2 | 4 | Planned |
| Status bar | 2 | 4 | Planned |
