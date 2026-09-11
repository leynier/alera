# Coordinator

## Coordinator Workflow

```bash
alera orchestration --json delegate --profile "Codex Sol" --spec "Review automated test coverage"
alera orchestration --json delegate --profile "Codex Sol" --spec "Implement the API" --new-workspace
alera orchestration --json task-create --task-title "Review Tests" --spec "Review automated test coverage"
alera orchestration --json run --agent codex --spec "Audit the repository"
alera orchestration --json run-list --workspace <workspace-id>
alera orchestration --json status --id <run-id>
```

`delegate` creates the task and spawns the declared profile. `--new-workspace` creates a child worktree first, inferring project, source branch, and parent from `ALERA_WORKSPACE_ID` or `--from-workspace`. Keep `task-create` plus `agent-spawn` when you need the primitives.

A failed delegation can leave a created workspace and task even when worker startup or acceptance fails. Preserve the returned IDs, inspect the current dispatch and terminal state, and retry the existing task only after confirming no worker is still executing. Do not repeat `delegate --new-workspace` blindly or remove the workspace automatically. Acceptance proves dispatch, while task completion and its validation establish the requested outcome.

Use `--agent codex|claude|copilot|cursor|agy|opencode|opencode2|pi|amp|grok`. The runtime may create workers through the built-in adapter registry.

To discover the launch configurations the user declared, read the catalog:

```bash
alera orchestration --json agent-profiles
```

Each profile carries `name`, `agentType`, `command`, `description`, and an optional `quotaGroup`. Use `description` to choose a profile for a stage, and pass its `agentType` and `command` to `agent-spawn`. Coordinator discovery is read-only: use declared profiles and commands. Profile administration is a separate user-requested task handled by the `alera-agent-profiles` skill. Profiles sharing a `quotaGroup` drain the same usage bucket, so falling back inside one group buys nothing. Stop scheduling with `run-stop --id`; add `--cancel-active` only when active work should receive cooperative cancellation. Run stop, task recovery, and dispatch interruption require the owning coordinator; `--force` is the audited administrative recovery path.

### Planning A Run

For a policy-managed run, propose its stage plan before creating stage-bound tasks. An existing approved policy remains valid; do not propose it again merely to repeat approval. Direct delegation already requested by the user does not need an additional policy proposal:

```bash
alera orchestration --json run-policy-propose --run <run-id> --policy-file plan.json
alera orchestration --json run-policy-show --run <run-id>
alera orchestration --json task-create --run <run-id> --stage implementation --spec "..."
```

```json
{
  "version": 1,
  "stallPolicy": "ask",
  "stages": [
    {"id": "implementation", "title": "Implementation", "profile": "Codex GPT-5.6-Sol", "fallbacks": ["Claude Sonnet 5"]}
  ]
}
```

Pick each stage's profile by reading the catalog descriptions; every profile named, preferred or fallback, must already exist there. Prefer a fallback from a different `quotaGroup`, since a fallback inside the same bucket buys nothing. `stallPolicy` is `ask`, `auto-failover`, or `wait`.

A proposed plan holds scheduling until the user resolves it, so propose before creating stage-bound tasks and then wait. Do not approve your own plan: approval is the user's decision. Prior explicit authorization can cover the same delegation or plan; do not ask for it again, but do not treat a pending runtime policy as approved or bypass its gate. A plan is revised by proposing again, not by re-approving.

For direct assignment, prefer `delegate` when the profile already exists. The primitive form is:

```bash
alera orchestration --json agent-spawn --agent codex --task <task-id> --title "Review Tests" --timeout-ms 90000
alera terminal --json wait --terminal <handle> --for dispatch-accepted --timeout-ms 60000
```

`agent-spawn --profile <name>` launches a declared profile, resolving the adapter and command host-side; it replaces `--agent` and cannot be combined with `--agent` or `--command`. For a task bound to a policy stage the coordinator selects the profile itself, preferring a fallback from a different quota group.

`agent-spawn` creates the dispatch before launching Codex and supplies a short first-turn bootstrap that tells the worker to accept and read its context. Other adapters use hook-based readiness injection. Its `--timeout-ms` value may not exceed the host acceptance limit of 90000 milliseconds. A startup failure removes only a terminal created by that spawn; add `--keep-on-failure` to retain it for diagnosis. Reused terminals are never removed.

Manual fallback is:

```bash
alera orchestration dispatch --task <task-id> --to <handle>
alera terminal write --handle <handle> --text "<returned bootstrap>" --submit
```

The default dispatch response returns the short bootstrap. Use `--return-preamble` only when the complete preamble is explicitly needed. If an agent is confirmed idle but its hooks are unavailable, `dispatch --inject --assume-agent codex` is an audited override.
