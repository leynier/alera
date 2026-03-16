# Session Persistence in Reference Orchestrators

**Date:** 2026-03-16
**Context:** Review of `reference_projects/` submodules to understand how each orchestrator handles session/conversation state persistence.

## Submodules Reviewed

| Project | Type | Persists Data? |
|---|---|---|
| `1Code` | Claude orchestration (Python) | Yes (SQLite) |
| `CodexMonitor` | Codex CLI wrapper (Python) | No (depends on native Codex) |
| `codex` | CLI + app-server (Rust/TypeScript) | Yes (JSON sessions on disk) |
| `jean` | Multi-provider orchestration (TypeScript) | Yes (SQLite) |
| `superset` | Dashboard | N/A |
| `t3code` | Codex orchestration (TypeScript) | Yes (SQLite + filesystem) |

## How Each Stores Sessions

### CodexMonitor

- No own storage. Relies entirely on native Codex sessions.
- Uses `thread/resume` to load history.
- If the native thread is deleted, all history is lost.

### t3code

- Stores session metadata in SQLite: thread ID, name, timestamps, status, model.
- Saves messages (text + role) and checkpoints with diffs per turn.
- On thread resume: builds a bootstrap input with recent message history as text context.
- Can function partially without native Codex (view history offline) but cannot truly rehydrate a deleted thread — the bootstrap is a lossy summary, not a byte-for-byte reconstruction.

### jean

- Stores full conversation history in SQLite: messages, tool calls, metadata.
- Supports multiple providers (Claude, Codex, OpenCode).
- Auto-names sessions via AI digest.
- Archives sessions on PR merge.
- Provider-agnostic storage — history survives provider switch.

### 1Code

- Stores messages, token usage, and session metadata in SQLite.
- Computes and persists stats (token counts, costs).
- Used mainly for search, analytics, and offline viewing.

### codex (native)

- Stores sessions as JSON files on disk (`~/.codex/sessions/`).
- Full message history including tool calls.
- This is what `thread/resume` reads from.

## Key Question: Is Own Storage Worth It If Codex Already Persists?

### Advantages of Own Storage

1. **Latency of tab switching** — local DB query vs. IPC `thread/resume` call.
2. **Offline UI** — show history without the provider running.
3. **Crash recovery** — detect incomplete runs, partial responses, dead PIDs.
4. **Provider-agnostic** — survive provider switches or provider deprecation.
5. **Provider doesn't support** — search across sessions, stats/analytics, export, per-turn diffs, auto-naming.
6. **Retention control** — provider may auto-delete old sessions; own storage is configurable.

### Key Disadvantage

- Duplicated data that **cannot be used to rehydrate the provider** byte-for-byte.
- UI showing full history while the agent has no context is worse than showing nothing (misleading).

### Recommended Approach

**Store what you need for UI and own features. Do not store expecting to fully re-inject into the provider.**

| What to Store | Why |
|---|---|
| Metadata (name, timestamps, model, status) | Listing, search, sorting |
| Messages (text + role) | Offline history, search |
| Token usage / costs | Stats, user limits |
| Checkpoints / diffs | Rollback UI, diff viewer |
| Partial responses | Crash recovery |

| What NOT to Store (or store as read-only) |
|---|
| Raw tool call input/output (display only, not for re-injection) |
| Provider sessionId (as reference, not as source of truth) |

For true rehydration, the t3code approach with `buildBootstrapInput` is the only viable path: format a textual summary of recent history and pass it as context to a new thread. It is lossy but it is the best possible without controlling the provider.
