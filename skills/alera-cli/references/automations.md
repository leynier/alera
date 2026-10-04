# Automations

Use the `alera-automations` skill for scheduled agent work. `alera automation` operates the shared desktop, mobile, and CLI catalog through the authenticated runtime host. A valid prompt, schedule, target, and launchable profile are sufficient. There are no approval, repository declaration, project approval, or profile permission gates.

```bash
alera automation --json list --workspace-id <workspace-id>
alera automation --json create --name 'Daily Review' --prompt 'Review changed files' --cron '0 9 * * 1-5' --timezone UTC --target fresh-tab --workspace-id <workspace-id> --profile-id <profile-id> --request-key daily-review
alera automation create --file definition.json --dry-run
alera automation edit --id <automation-id> --prompt-file prompt.txt
alera automation run-now --id <automation-id>
alera automation pause --id <automation-id> --active-runs continue-active
alera automation resume --id <automation-id>
```

Creation is Active unless `--draft` is supplied. Edits preserve the current state and apply to future runs. The target type is always explicit; chosen target fields can use the current terminal context. `create --file` accepts partial JSON without IDs, revisions, actors, or timestamps. `edit --file` accepts a partial patch. `--request-key` makes repeated creation idempotent. `readiness` validates without saving, and `preview-schedule` lists upcoming dates.

`run-now` needs no repeated precheck or overlap options and does not activate scheduling. `approve` is a deprecated alias of `resume`; `policy` has been retired. Existing Tab requires a captured live conversation. Watching a terminal is read-only; explicit Take Over stops recovery and preserves resources.

The runtime must be running. Creating an automation does not enable autostart. Missed occurrences default to Skip; interrupted admitted runs reconcile ownership and recover in their preserved workspace with a bounded retry budget. The CLI automatically supplies the current attempt ID on lifecycle calls from an automation terminal.
