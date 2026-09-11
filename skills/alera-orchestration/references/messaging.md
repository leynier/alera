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

Use `--body-file` or `--body-stdin` for multiline content. Operational messages become expired or obsolete when their scope ends. List commands return `{kind, items, filters}`; use `items` in automation. Terminal and task waits are held by the runtime host and make a final state check at timeout.
