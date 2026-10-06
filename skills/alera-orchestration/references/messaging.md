# Messaging And Diagnostics

```bash
alera orchestration send --to <handle|@group> --subject "Status" --body "Details"
alera orchestration inbox --terminal <handle> --direction inbox
alera orchestration inbox --terminal <handle> --direction outbox
alera orchestration check --wait --types escalation,decision_gate --timeout-ms 300000
alera orchestration terminal-show --handle <handle>
alera terminal list
alera terminal read --handle <handle> --max-bytes 65536
alera terminal write --handle <handle> --text "continue" --enter
alera terminal write --handle <handle> --stdin --submit
alera terminal prune
alera terminal prune --apply
```

`--enter` sends content first and a separate delayed carriage return. Use `--submit` for bracketed-paste TUI input. `terminal prune` is dry-run by default and only removes stopped terminal tabs when `--apply` is present.

## Inbox Questions

A banner that starts with `External question from ext:...` comes from a caller outside Alera (another session, a script, or the desktop and mobile apps). The caller cannot read your terminal: put the complete answer in the reply, and answer only through the command in the banner.

```bash
alera orchestration reply --id <question-id> --body "<complete answer>"
alera orchestration reply --id <question-id> --body-file <path-to-answer>
```

Write a long or multiline answer to a file and pass `--body-file`; it works in every shell. Do not use a bare `--body-stdin` from the terminal: it waits for an end of input the terminal never sends.

To ask without blocking your turn, use `alera orchestration ask --to <handle> --question "..." --no-wait`; it prints the question id. The answer is pasted on your next turn, or read it earlier with `alera inbox wait --question <id> --timeout 10m`. `alera inbox conversations` lists agent conversations read-only.

Use `--body-file` or `--body-stdin` for multiline content. Operational messages become expired or obsolete when their scope ends. List commands return `{kind, items, filters}`; use `items` in automation. Terminal and task waits are held by the runtime host and make a final state check at timeout.
