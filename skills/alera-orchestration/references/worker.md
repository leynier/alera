# Worker

There is no accept step and no heartbeat. Your first worker command (`context`, `ask`, `escalate`, or `complete`) tells Alera you started, and your terminal activity keeps the task alive.

```bash
alera orchestration --json context
alera orchestration complete --summary "What was done and what remains"
```

- `complete` records the result exactly once. Only `--summary` is required. Add `--kind failure` when the task could not be done; a failure consumes the task's failure budget and may return it to ready.
- Optional evidence: `--files "path/a,path/b"`, `--artifacts '<json array>'`, `--validation '<json array>'`. When the task has a role contract or a result schema (shown by `context`), supply what it asks for, with `--result-extra '{"field":"value"}'` for extra schema fields.
- After completing, end the turn. The terminal stays open for reuse.
- Report a blocker the coordinator must act on:

```bash
alera orchestration escalate --subject "Blocked: missing credentials" --body "Details"
```

- Ask the coordinator with `alera orchestration ask --to <coordinator-handle> --question "..." [--options "A,B"]`. While a dispatch is active the host routes the question to the dispatch's current coordinator, even after a transfer. Never open a local user-input prompt the coordinator cannot see. Add `--no-wait` to keep working (see [messaging](messaging.md)).
- Read messages sent to you with `alera orchestration check`, or list recent ones with `alera orchestration messages`.
- If the host marked you stalled, your next command or terminal output revives the dispatch, and `complete` still works.

Never send lifecycle state as a message or edit task status directly.
