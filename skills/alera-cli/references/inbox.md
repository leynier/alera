# Inbox

Ask an Alera agent a question from any process on the machine and read the answer later. You do not need an Alera terminal.

```bash
export ALERA_EXTERNAL_INBOX=ext:my-session   # or pass --inbox; defaults to ext:user
alera inbox --json targets --workspace <workspace-id>
q=$(alera inbox --json ask --workspace <workspace-id> --agent codex --body-stdin <<'EOF' | jq -r .questionId
What does the migration change?
EOF
)
alera inbox --json wait --question "$q" --timeout 30m   # exit 2 on timeout
alera inbox --json ask --thread "$q" --body "And the rollback?"
alera inbox --json wait --question "$q" --after <cursor> --timeout 30m
alera inbox show --question "$q"
alera inbox threads [--status answered] [--all-inboxes]
alera inbox cancel --question "$q"           # only before the agent saw it
alera inbox purge --inbox ext:my-session --confirm
alera inbox conversations [--workspace <id>] # read-only agent-to-agent threads
alera inbox conversation --thread <thread-id>
```

Choose the agent with `--to <terminal-handle>`, or `--workspace` plus `--agent` when the workspace runs several agents; an ambiguous choice fails with the candidates. A question reaches the agent when its turn ends and expires after 5 hours if it never does (`--expires-in`). A recipient accepts at most 20 undelivered questions. `wait` reports `answered`, `message`, `cancelled`, `expired`, `purged` or `timeout` with a `cursor`; pass the cursor as `--after` to read only what is new. Answers are only what the agent sends with `alera orchestration reply`; nothing typed in its terminal is captured. Inbox history is kept 7 days.
