# Messaging And Diagnostics

```bash
alera orchestration send --to <handle|@group> --subject "Status" --body "Details" [--delivery now]
alera orchestration check [--wait --types escalation,question --timeout-ms 300000]
alera orchestration messages --terminal <handle> --direction inbox
alera orchestration messages --terminal <handle> --direction outbox
alera orchestration ask --to <handle> --question "..." [--options "A,B"] [--no-wait]
alera orchestration reply --id <message-id> --body "..."
```

## Delivery

A message reaches an idle agent at once. For a working agent, `--delivery now` pastes it mid-turn when that agent queues input (Claude Code and Codex); otherwise it waits for the turn to end. `ask` defaults to `now`, `send` and `reply` to `turn-end`. An agent waiting on a prompt never gets a paste. Responses report `deliveryMode`: `pasted_now`, `queued_at_turn_end`, `check` (a coordinator reads it with `check`), or `unavailable`.

`ask` waits for the answer. `--no-wait` prints the question id at once; the answer reaches your terminal on its next turn, or read it earlier with `alera inbox wait --question <id> --timeout 10m`.

## Banners

Delivered messages arrive as banners:

```text
[Alera] Question from ext:ci-review via Alera desktop, id <id>
<body>
Reply: alera orchestration reply --id <id> --body "..." (the sender cannot read this terminal)
```

Messages between agents start with `[Alera] Message from <handle>, id <id>`. A question from `ext:` comes from outside Alera (another session, a script, or the desktop and mobile apps): the sender cannot read your terminal, so put the complete answer in the reply and answer only with `reply`. Write a long or multiline answer to a file and pass `--body-file`; do not use a bare `--body-stdin` from the terminal, which waits for an end of input it never gets. When a batch is truncated, read the rest with `alera orchestration messages --terminal <handle>`.

An agent may also write to an inbox first: `send --to ext:<name>` without `--thread-id` opens a thread, and `--thread-id` continues one between that inbox and you.

## Terminals

```bash
alera orchestration terminal list
alera orchestration terminal show --handle <handle>
alera orchestration terminal wait --terminal <handle> --for agent-ready --timeout-ms 60000
alera orchestration terminal prune [--apply]
alera terminal read --handle <handle> --max-bytes 65536
alera terminal write --handle <handle> --text "continue" --enter
```

`terminal wait --for` takes `process-started`, `agent-detected`, `agent-ready`, or `dispatch-accepted` (the worker's first command was received). `terminal prune` is a dry run unless `--apply` is present. List commands return `{kind, items, filters}`; use `items` in automation.
