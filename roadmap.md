# Alera Roadmap

Comprehensive feature roadmap for Alera. Each feature is scored on two axes:

- **Difficulty** (1–5): estimated implementation effort (1 = trivial, 5 = very complex)
- **Utility** (1–5): how useful or frequently used the feature is in an app of this type (1 = niche, 5 = essential)

---

## Agent Integration

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Agent auto-detection & registry | 3 | 5 | Detect installed CLI agents (Claude Code, Codex, Gemini, etc.) and expose a selection UI |
| Agent status tracking | 3 | 5 | Real-time idle/active/waiting state with visual dots per worktree |
| Agent lifecycle hooks | 4 | 4 | Fire hooks when agents start/stop; relay for inter-process communication |
| Agent awake service | 2 | 3 | Prevent system sleep while agents work (caffeinate / lid-sleep) |
| Agent trust presets | 2 | 3 | Per-agent permission and trust configuration |
| Agent interrupt intent | 2 | 4 | Graceful agent interruption protocol |
| Orchestration between agents | 5 | 5 | Inter-agent messaging, task dispatch, coordinator loop, decision gates |

---

## Terminal

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Terminal search | 2 | 5 | In-terminal text search across scrollback |
| Terminal session persistence | 4 | 4 | Save/restore terminal buffers across app restart (not just tab records) |
| Terminal quick commands | 2 | 3 | Shortcut palette for frequently used terminal commands |
| Floating terminal panel | 3 | 3 | Floating, resizable terminal overlay with window controls |
| Terminal ligatures | 2 | 2 | Font ligature support in terminal rendering |
| Ghostty settings import | 2 | 2 | Import terminal settings from Ghostty config files |
| Terminal stream protocol | 4 | 3 | Protocol for streaming terminal output to mobile/remote clients |
| Tab cycling & reopen closed tab | 2 | 4 | Cycle tabs by type/recent order; reopen recently closed tabs |

---

## Editor & Files

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| File Explorer panel | 4 | 5 | Tree-based file browser with virtual rows, git-ignored toggle, inline rename |
| Code edition with LSP support | 5 | 5 | Full code editor with language server protocol integration |
| Markdown editor | 4 | 3 | WYSIWYG markdown editing with toolbar, slash menu, code blocks, tables, mermaid |
| Open in with other softwares | 2 | 4 | Open files/folders in VS Code, Cursor, Zed, custom editors, file manager |
| Autosave | 2 | 4 | Automatic file saving with configurable behavior |
| Editor scroll restore | 1 | 3 | Persist and restore scroll position across sessions |
| External file watch | 2 | 4 | Detect external file changes and prompt reload |
| PDF viewer | 3 | 2 | Render PDFs with in-document search |
| CSV viewer | 2 | 2 | Tabular display for CSV/TSV data |
| Jupyter Notebook viewer | 3 | 2 | Render `.ipynb` files with cell outputs |
| Image viewer | 2 | 3 | Image display with zoom and pan controls |
| Mermaid viewer | 2 | 2 | Standalone rendered mermaid diagram viewer |

---

## Search

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Search panel | 3 | 5 | Text search across workspace files with include/exclude patterns |

---

## Source Control & Diffs

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Diff panel | 4 | 5 | Unified diff view with file tree navigation |
| Diffs per file | 3 | 5 | File-level diff view with line stats |
| Diffs global | 3 | 4 | Aggregated diff across all changed files |
| Git status with operations | 4 | 5 | Staging, commit, pull, push, discard with full UI |
| Commit and PR messages with AI | 3 | 4 | AI-generated commit messages and PR descriptions |
| Conflict view and resolver | 4 | 4 | Visual conflict display with merge controls |
| Conflict resolution with AI | 4 | 3 | AI-assisted three-way merge conflict resolution |
| Git history panel with graph | 4 | 4 | Commit history browser with visual branch/merge graph |
| Diff annotations & inline comments | 4 | 3 | Comment threads on diff lines with popovers |
| Send diff annotations to agent | 3 | 4 | Send annotated diffs directly to agents for action |
| Image diff | 3 | 2 | Side-by-side image comparison for binary diffs |

---

## Integrations & Providers

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Checks panel (CI/CD) | 3 | 4 | CI status monitoring; implies GitHub/GitLab/Azure integration |
| GitHub Projects integration | 4 | 3 | Full project board with columns, cards, filtering, inline editing |
| Linear integration | 4 | 2 | Linear SDK, issue workspace, item drawer, team selection |
| Multi-account support | 3 | 3 | Account switcher, manage multiple accounts per provider |

---

## Browser

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Browser tab | 4 | 4 | Embedded Chromium browser with address bar and navigation |
| Browser Use | 5 | 4 | Full browser automation: snapshot, click, fill, screenshot, eval, etc. |
| Browser session profiles | 3 | 3 | Create, clone, switch browser profiles with cookie import |

---

## Workspace & Navigation

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Quick Open / Command Palette | 3 | 5 | Fuzzy file search (Cmd+P) and command execution (Cmd+Shift+P) |
| Worktree navigation history | 2 | 4 | Back/forward navigation stack between worktrees |
| Worktree sleep/wake | 3 | 3 | Sleep worktrees to save resources; wake when needed |
| Worktree comments & metadata | 2 | 3 | Display names, comments, issue links on worktrees |
| Worktree multi-selection | 2 | 3 | Select multiple worktrees for batch operations |
| Worktree manual ordering | 2 | 3 | Drag-and-drop worktree reorder with persistence |
| Smart workspace naming | 2 | 3 | Intelligent auto-naming suggestions for new worktrees |
| Workspace cleanup dialog | 2 | 3 | Bulk cleanup of stale worktrees |
| Status bar | 2 | 4 | SSH status, ports, resources, update status, disk usage |
| UI zoom controls | 1 | 3 | Zoom in/out/reset for the entire UI |
| Global file drop | 2 | 3 | Drag files from OS into the app |

---

## Kanban & Task Management

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Kanban panel | 3 | 3 | Kanban board with status lanes, cards, drag-drop |

---

## Automations

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Automations system | 4 | 4 | Cron-style scheduled agent workflows with templates and run history |

---

## Activity & Notifications

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Activity feed | 3 | 5 | Unified activity feed with agent completion tracking |
| Notification system | 3 | 4 | Agent notifications, unread tracking, OS dock badge |
| Agent auto-acknowledge | 1 | 3 | Mark viewed agent completions as read automatically |

---

## Usage & Analytics

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Per-agent usage charts | 3 | 4 | Daily usage visualization per agent provider |
| Cost tracking | 3 | 4 | API cost monitoring and visualization |
| Share/export usage | 2 | 2 | Export or share usage stats |

---

## Resource & System Management

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Resource manage | 3 | 3 | System resource consumption monitoring |
| Space analyzer | 2 | 3 | Disk space tracking and compaction per workspace |
| Port scanning & dev server management | 3 | 4 | Auto-detect open ports, panel listing active dev servers |

---

## Remote & Mobile

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| SSH | 5 | 4 | SSH targets, remote PTY, remote filesystem, remote git |
| Computer Use | 5 | 3 | Native desktop automation via Accessibility APIs |
| Mobile App | 5 | 3 | Companion app for monitoring worktrees, viewing terminals, sending commands |

---

## CLI

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Alera CLI | 4 | 4 | Full CLI: worktrees, terminals, repos, automations, orchestration, browser |

---

## Settings & Customization

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Customizable keyboard shortcuts | 3 | 4 | File-based keybinding config with import/export and conflict detection |
| Skills system | 3 | 3 | Browse, manage, and configure agent skills |
| MCP configuration management | 3 | 3 | Manage Model Context Protocol server configurations |
| Project configuration file (alera.yaml) | 3 | 4 | Per-repo setup scripts, hooks, symlinks, sparse checkout presets |

---

## Onboarding & Discovery

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Onboarding wizard | 3 | 4 | Multi-step first-run setup for agents, repos, theme, integrations |
| Feature tips & discovery | 2 | 3 | Contextual hints for undiscovered features |

---

## Voice

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Voice / dictation / STT | 4 | 2 | Offline speech-to-text via sherpa-onnx, dictation controller, voice settings |

---

## Telemetry & Diagnostics

| Feature | Difficulty | Utility | Notes |
|---|:---:|:---:|---|
| Telemetry & analytics | 3 | 3 | Usage analytics with consent management |
| Crash reporting | 2 | 3 | Crash report dialog and collection |
| Diagnostic bundles | 2 | 2 | Collect diagnostic info for user support |
| Privacy settings | 2 | 3 | Opt-in/out controls for telemetry |

---

## Score Summary

### Top features by Utility (5/5)

| Feature | Difficulty |
|---|:---:|
| Agent auto-detection & registry | 3 |
| Agent status tracking | 3 |
| Terminal search | 2 |
| File Explorer panel | 4 |
| Code edition with LSP support | 5 |
| Search panel | 3 |
| Diff panel | 4 |
| Diffs per file | 3 |
| Git status with operations | 4 |
| Orchestration between agents | 5 |
| Quick Open / Command Palette | 3 |
| Activity feed | 3 |

### Lowest difficulty with high utility (Difficulty ≤ 2, Utility ≥ 4)

| Feature | Difficulty | Utility |
|---|:---:|:---:|
| Terminal search | 2 | 5 |
| Open in with other softwares | 2 | 4 |
| Tab cycling & reopen closed tab | 2 | 4 |
| Autosave | 2 | 4 |
| Worktree navigation history | 2 | 4 |
| Status bar | 2 | 4 |
