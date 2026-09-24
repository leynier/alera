# Worker

## Worker Contract

The dispatch preamble installs a terminal-scoped context. Execute acceptance before doing work:

```bash
alera orchestration dispatch-accept
alera orchestration --json context
```

Use context-aware lifecycle commands:

```bash
alera orchestration heartbeat --phase reviewing
alera orchestration escalate --subject "Blocked" --body "Missing credentials"
alera orchestration complete --summary "Review completed" --completion-kind success --artifacts '[]' --files-modified "path/a" --validation '[]'
```

If the task defines a custom result schema, add its properties with `--result-extra '{"field":"value"}'`.

- `complete` is atomic and required exactly once. `completion-kind failure` consumes execution failure budget and may return the task to ready.
- `worker-done --task --dispatch --summary` is the idempotent explicit recovery form.
- Never use `send --type worker_done`, `send --type heartbeat`, or arbitrary task status mutation; protocol v2 rejects them.
- After successful completion, stop the turn. Default policy returns immediately and leaves the terminal open for reuse.
- Use `ask` for coordinator questions. While a dispatch is active, the host routes the question to the dispatch's current durable coordinator even if the run was transferred after its preamble was injected. Do not open a local user-input prompt the coordinator cannot see.

For the installed compact command contract, use `alera orchestration worker-help`. For message and terminal inspection commands, read [messaging](messaging.md).
