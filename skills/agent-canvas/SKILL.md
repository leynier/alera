---
name: agent-canvas
description: Publish structured Agent Canvas updates for the current Alera terminal and wait for durable decisions.
metadata:
  version: 1
---

# Agent Canvas

Agent Canvas is the shared Alera surface for an agent run. The runtime host owns persistence, revisions, decisions, retention, and events. Use the `alera canvas` command instead of writing to an application socket or modifying runtime SQLite directly.

## Identity

Run inside an Alera terminal so `ALERA_WORKSPACE_ID` and `ALERA_TERMINAL_SESSION_ID` identify the one canvas owned by that terminal. `ALERA_TAB_ID` and `ALERA_AGENT_TYPE` are used when available. A canvas is scoped by workspace and terminal session.

## Contract

```bash
alera canvas capabilities --json
alera canvas catalog --workspace-id <workspace-id> --history --json
alera canvas examples --json
alera canvas publish --stdin --expected-revision <revision> --json
alera canvas events --workspace-id <workspace-id> --follow --json
alera canvas wait --decision-id <decision-id> --timeout-ms 600000 --json
alera canvas complete --canvas-id <canvas-id> --json
alera canvas close --canvas-id <canvas-id> --json
```

`publish` accepts one JSON document or newline-delimited JSON objects. The command preserves the last valid revision when validation or an expected-revision check fails. Retry a conflict by reading the catalog and publishing against its returned revision.

Decision requests remain durable until resolved or timed out. Resolving an already resolved decision is idempotent, and a timeout does not cancel the agent run.

## Surface Rules

Use the ten supported components reported by `capabilities`. Prefer semantic coalescing and publish only meaningful changes. Do not include arbitrary commands, shell text, functions, source code, external requests, URLs, or unvalidated paths in actions. Immediate navigation and typed confirmation actions are handled by Alera; destructive actions require an explicit confirmation and remain scoped to the owning canvas.
