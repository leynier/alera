# Git Worktree Practices in Reference Projects

## Context

Analysis of how each orchestrator in `reference_projects/` handles git worktrees, their patterns, and best practices.

---

## Reference Projects Analyzed

| Project | Role | Language |
| --- | --- | --- |
| `codex` | Primary reference (CLI, app-server, protocol) | Rust / TypeScript |
| `claude-code` | Agent-based task execution | TypeScript |
| `codex-monitor` | Monitoring daemon for Codex sessions | TypeScript |
| `jean` | Session management with teardown workflows | TypeScript |
| `t3code` | Alternative orchestrator approach | TypeScript |

---

## Core Pattern: Isolated Worktrees for Parallel Agents

All orchestrators follow the same fundamental principle: **each agent/task gets its own git worktree** to avoid conflicts when multiple agents work in parallel on the same repository.

### Base Pattern

```bash
git worktree add <worktree-path> -b <branch-name>
# agent works in <worktree-path>
#完成后合并回主线或创建PR
git worktree remove <worktree-path>
```

---

## 1. Codex (`reference_projects/codex`)

### Worktree Lifecycle

- **Creation**: Creates a temporary worktree per agent session under a configurable base directory.
- **Branch naming**: Follows the pattern `agent/<task-id>/<short-description>` for branch names.
- **Isolation**: Each agent operates fully within its worktree — no shared state between agents.
- **Cleanup**: Worktrees are removed after task completion; branches are merged or deleted based on outcome.

### Key Design Decisions

- Uses `git worktree add --detach` initially, then creates a named branch before any commits.
- Implements a **lease/heartbeat** system: worktrees have an associated TTL; if the agent dies, stale worktrees are automatically cleaned up.
- Shared worktree base directory is configurable via environment variable.

### Security Practices

- Worktrees enforce sandbox boundaries: agents cannot escape their worktree directory.
- File system permissions are set to prevent cross-worktree access.
- Git hooks are copied from the main worktree to each agent worktree.

---

## 2. Claude Code (`reference_projects/claude-code`)

### Worktree Integration

- Uses `git worktree add` with automatic branch creation.
- Provides the `EnterWorktree` / `ExitWorktree` tool interface for agents to manage worktree sessions.
- Worktrees are created under `.claude/worktrees/` within the project.

### Key Features

- **Lazy creation**: Worktrees are only created when explicitly requested, not preemptively.
- **Session-scoped**: Worktree lifecycle is tied to the agent session.
- **Keep or remove**: On exit, the user chooses whether to keep the worktree and branch or discard them.
- **Context isolation**: CWD-dependent caches, system prompt sections, and memory files are cleared on worktree exit to prevent state leakage.

### Branch Naming

- Auto-generates random branch names if none is provided.
- Branch is based on HEAD of the current branch at creation time.

---

## 3. CodexMonitor (`reference_projects/codex-monitor`)

### Apply-to-Parent System

- Monitors agent worktrees for completed work.
- Implements an **apply-to-parent** pattern: when an agent finishes work in a worktree, the changes are applied back to the parent/main context.
- Tracks worktree state via filesystem watchers and git events.

### Worktree State Machine

```
created -> active -> completed -> merged / discarded
                      |
                   failed (cleanup)
```

- Transitions are tracked in a local state store.
- Failed worktrees trigger automatic cleanup to prevent accumulation.

---

## 4. Jean (`reference_projects/jean`)

### Teardown Workflow

- Implements a formal teardown script system for worktree lifecycle.
- Each worktree has an associated teardown script that runs on completion, failure, or cancellation.
- Supports archiving: completed worktrees can be archived (compressed) rather than immediately deleted.

### Key Features

- **Archival pattern**: Instead of immediate deletion, worktrees are archived to a configurable archive directory.
- **Teardown hooks**: Pre-teardown and post-teardown hooks allow custom cleanup logic (e.g., running final tests, collecting artifacts).
- **Named worktrees**: Uses human-readable names for easier identification during debugging.

---

## 5. t3code (`reference_projects/t3code`)

### Shared Worktrees

- Uses git shared worktrees (`--shared` flag) to reduce disk usage when multiple agents work from the same base.
- Implements **lazy worktree creation**: worktrees are created on-demand when an agent first needs to write, not at session start.

### Key Features

- **Shared object store**: Multiple worktrees share the same `.git` objects directory to minimize disk and memory usage.
- **Branch isolation with shared objects**: Each worktree has its own branch and working directory, but shares the git object database.
- **Concurrency model**: Uses file locks to prevent simultaneous writes to the shared object store.

---

## Cross-Cutting Patterns

### Common Practices

1. **Isolation**: Every orchestrator isolates agent work in separate worktrees.
2. **Automatic cleanup**: All implement some form of stale worktree detection and cleanup.
3. **Branch-per-task**: Each agent/task gets its own branch.
4. **Base directory management**: Worktrees are grouped under a single configurable directory.

### Naming Conventions

| Project | Pattern |
| --- | --- |
| Codex | `agent/<task-id>/<description>` |
| Claude Code | Random name or user-provided |
| Jean | Human-readable names |
| t3code | Task-derived names |

### Cleanup Strategies

| Strategy | Used By |
| --- | --- |
| Immediate removal on completion | Codex, Claude Code |
| State machine with conditional cleanup | CodexMonitor |
| Archive before removal | Jean |
| Lazy cleanup with TTL/heartbeat | Codex |

---

## Key Takeaways for Alera

1. **Worktree isolation is non-negotiable** for multi-agent parallel work.
2. **Branch naming should be deterministic** (e.g., `agent/<task-id>/<description>`) for traceability.
3. **Stale worktree cleanup is essential** — implement either a heartbeat/TTL system or a state machine.
4. **Consider the apply-to-parent pattern** from CodexMonitor for merging agent work back to main.
5. **Shared worktrees** (t3code pattern) can significantly reduce resource usage in high-concurrency scenarios.
6. **Teardown hooks** (Jean pattern) provide a clean extension point for custom cleanup logic.
