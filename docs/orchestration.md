# Inter-Agent Orchestration

Alera orchestration is owned by the Rust runtime-host. Tasks, dispatches, messages, decision gates, coordinator runs, and administrative audit events are persisted in the runtime SQLite database; all mutations pass through the authenticated host actor.

## Contract Versions

- Terminal-host protocol: 4.
- Orchestration protocol: 2.
- Dispatch preamble: 2.
- Installed skill contract: 3.

`alera version --json` reports the CLI build and expected contracts, then queries an already-running compatible runtime host for its actual build and contract versions. Cargo builds embed `ALERA_BUILD_COMMIT` when supplied and otherwise resolve the current Git commit at build time. Host fields are `null` and `runtimeHostAvailable` is `false` when no compatible host is reachable; the command never invents host equality from the CLI build.

Runtime-host features are negotiated additively. Terminal inspection and prune commands require `orchestrationTerminalInspectionV1`, waits require `orchestrationWaitV1`, explicit agent overrides require `orchestrationAssumeAgentV1`, the agent profile catalog requires `orchestrationAgentProfilesV1`, and deferred Enter/submit requires `terminalDeferredInputV1`; the CLI asks for a host restart instead of sending unsupported RPCs.

The v2 schema is incompatible at the SQL constraint level, so the runtime performs a transactional table rebuild that preserves v1 messages, tasks, dispatches, gates, and runs while filling new ownership and scope fields with conservative defaults. Unknown future schema versions fail closed instead of deleting state.

## Runs And Ownership

Runs and tasks carry `workspaceId`, `runId`, `coordinatorHandle`, and `assigneeHandle`. Multiple workspaces can coordinate concurrently, but a workspace can have at most one active run. A coordinated run adopts ready/manual tasks in its workspace that belong to its coordinator. Creating a task for an existing run requires the same workspace and coordinator; injected dispatches likewise require the target terminal to belong to the task workspace.

Coordinator authority resolves from the run or task, never from whichever terminal calls dispatch. `dispatch` rejects `from == to` unless `--allow-self-dispatch` is present. Stopping runs, interrupting dispatches, recovering tasks, cancellation, and ownership transfer require the current coordinator or an audited `--force --reason` action. A task attached to a run cannot transfer independently; transfer the run so its durable tasks, active dispatches, and in-memory coordinator remain aligned.

```bash
alera orchestration task-create --workspace <workspace-id> --spec "Review tests"
alera orchestration run --workspace <workspace-id> --agent codex --spec "Audit the repository"
alera orchestration run-list --workspace <workspace-id>
alera orchestration run-show --id <run-id>
alera orchestration run-stop --id <run-id> [--cancel-active] --reason "Stopped by coordinator"
```

`task-create`, `agent-spawn`, and `run` default `--workspace` from `ALERA_WORKSPACE_ID`. Use `alera orchestration current` to inspect the current workspace and terminal identity.

`run-stop` is graceful by default: it stops new scheduling while active workers retain authority to finish and persists the supplied reason on the run. `--cancel-active` applies cooperative cancellation to active tasks. Only the owning coordinator can stop the run normally; `--force` is reserved for audited administrative recovery, and forced child cancellations retain the administrative actor in their audit records.

## Agent Profile Catalog

An agent profile is a user-declared launch configuration a run can dispatch to. Each profile carries a unique name, an adapter type from the built-in registry, a launch mode, a custom prompt, a free-text description used as a routing signal, and an optional quota group. Profiles are user configuration, not run state: they live in the runtime schema next to `sshTargets`, so resetting orchestration state never destroys them.

```bash
alera orchestration agent-profiles --json
```

The CLI surface is read-only by design. A coordinator discovers what it may dispatch to and what each option is good for, but only the user creates or edits profiles, through Settings -> Agent Profiles. The orchestrator therefore picks from a closed list the user approved instead of inventing launch commands.

The adapter type is required because the registry is more than a command: it decides how the host detects readiness, injects the dispatch preamble, and forces submission. The host rejects a profile whose adapter is not in `AGENT_ADAPTERS`.

Before creating a worker tab, the host persists `agentProfileLaunchV1`: the resolved profile identity and concrete OCC revision, adapter, launch mode, effective Command line or Managed executable and argv, local target/platform, and initial-delivery policy. Recovery launches from that immutable snapshot and does not resolve the mutable profile again, so later profile edits cannot change an existing worker. New profiles start at revision `0`, updates advance that revision, and every launch captures the exact revision it resolved. Command lines remain opaque interactive-shell input; the host never splits or reparses them. The snapshot excludes environment and provider session state. Tabs without a snapshot continue through the legacy readers.

For delivery policies that replay on PTY restart, the tab separately retains the initial bootstrap until the tab is deleted. `pendingAgentPrompt` is a consumable per-PTY copy: the first matching ready event spends it, while a newly minted PTY rearms it from the retained bootstrap. Attaching again to the same PTY does not rearm it. Both bootstrap fields are removed from tab protocol projections and are used only for initial terminal delivery; they are not provider-resume data.

Managed mode exposes the supported model, effort, persona, permission, sandbox, and trust controls for the selected adapter. Missing options deliberately defer to that agent's own configuration. The host validates the structured configuration and quotes the resulting executable and arguments for the actual platform shell only when the terminal is spawned. Command mode remains available for advanced or unsupported CLI options; its value must be the interactive form the adapter expects because a one-shot mode cannot satisfy the accept/heartbeat/complete worker contract. Existing profiles are migrated as Command profiles without changing their behavior.

A managed Codex profile carries a second effort setting, `planModeEffort`, which becomes `-c plan_mode_reasoning_effort=<value>`. It governs only how hard Codex thinks while it is in plan mode, and the profile cannot put it there: Codex 0.146 has no flag or config key for the startup collaboration mode, which is entered with Shift+Tab or `/plan` in the TUI (`collaboration_mode` is an app-server per-turn parameter, not a config file key). The editor says so on the control rather than implying the profile selects the mode. The upstream request is openai/codex#13942.

A managed Claude profile can also pass `--allow-dangerously-skip-permissions` through `allowSkipPermissions`. That flag only makes bypass reachable inside the session; `permissionMode: bypassPermissions` is what starts there, and the two are independent on purpose. It still counts as a reduced-protection marker, so turning it on asks for confirmation before the profile is saved.

A managed Claude profile may also carry an optional `ccsProfile`. When it is set, the launch replaces the executable with `ccs` and passes the profile as its first positional argument, followed by the same Claude flags, because that is the switcher's own contract (`ccs <profile> [claude-args...]`). The value must be a single name that does not start with a dash: it is positional, so a dash-prefixed value would be read as an option of the switcher itself. Only the Claude adapter accepts the key; the host rejects it anywhere else. `ccs` points `CLAUDE_CONFIG_DIR` at the account instance directory, whose `settings.json` is a symlink chain to `~/.claude/settings.json`. That user file is where Alera installs the agent-status hooks, because it is the only settings source such a session reads; see [`architecture.md`](architecture.md) for why the instance directory cannot hold them and how Grok is kept from running them.

Command mode also has to say where the dispatched prompt goes, because the user writes the whole launch line there. That follows the adapter's `startup_prompt`, which names the shape that agent's own CLI accepts for starting interactively with a prompt already submitted: a positional argument after the option terminator for Codex, Claude, Cursor and Grok Build; a bare positional for `pi`, which rejects the terminator and gets a leading space instead when the prompt opens with a dash; a single `--interactive=`, `--prompt-interactive=` or `--prompt=` token for Copilot, Antigravity and OpenCode; standard input for Amp; and a terminal paste after the first semantic ready event for fx. The editor states which one applies and previews the resulting line wherever the prompt reaches the command line.

The profile's Custom Prompt is added after the prompt supplied by New Workspace or `orchestration agent-spawn`, when it is non-empty. The project's `new_workspace.prompt_append` is added last, so every delivered prompt has the order user prompt, profile instructions, then project instructions, with blank lines between non-empty sections.

The quota group declares which profiles drain the same usage bucket. Alera never measures, predicts, or verifies quota here; the grouping is an assertion the user makes, and its only purpose is to let a later fallback prefer a candidate from a different bucket.

The app manages the catalog with `agentProfile.list`, `agentProfile.upsert`, and `agentProfile.remove`, applies successful mutations immediately, and reconciles them with the debounced `agentProfilesChanged` snapshot. Managed mode is advertised through the additive `orchestrationManagedAgentProfilesV1` capability and does not change the terminal host protocol version.

## Execution Policy

A run may carry an execution policy: a stage plan the user approves before the coordinator is allowed to dispatch. The policy names a preferred agent profile per stage plus an ordered fallback list, and tasks reference a stage through `task-create --stage`.

```bash
alera orchestration run-policy-propose --run <run-id> --policy-file plan.json
alera orchestration run-policy-show --run <run-id>
alera orchestration run-policy-approve --run <run-id>
alera orchestration run-policy-reject --run <run-id> --reason "Wrong stage split"
```

```json
{
  "version": 1,
  "stallPolicy": "ask",
  "stages": [
    {
      "id": "implementation",
      "title": "Implementation",
      "profile": "Codex GPT-5.6-Sol",
      "fallbacks": ["Claude Sonnet 5"]
    }
  ]
}
```

Proposal validates the plan against the catalog: stages must be non-empty with unique ids, `stallPolicy` must be `ask`, `auto-failover`, or `wait`, and every referenced profile, preferred or fallback, must already exist. An unknown profile is an error rather than a warning, because it would otherwise only surface at dispatch, long after the user decided. A stage id a run does not declare is rejected by `task-create --stage` for the same reason.

Approval state is `none`, `draft`, `approved`, or `rejected`. Only `draft` holds scheduling: `coordinator_dispatch_ready_tasks` returns early while a proposal is unresolved. A run with no policy, an approved one, or a rejected one all schedule exactly as runs did before policies existed, so the feature is opt-in and changes no existing behavior. Approving or rejecting twice is refused so a decision cannot be silently overwritten; revising a plan means proposing again. Approvals and rejections are recorded in `orchestrationAuditEvents`, and a rejection requires a reason.

Decision gates are not reused for this: `orchestrationDecisionGates.task_id` is `NOT NULL`, so a run-scoped gate would need a destructive table rebuild, and creating a gate closes the active dispatch, which is the wrong semantics for a plan. The app surfaces pending plans through Execution Plans in the application menu.

## Agent Spawn And Readiness

`agent-spawn` creates or selects a terminal, starts the requested agent, delivers its bootstrap through the registered adapter, and waits for acceptance. Every adapter receives a short bootstrap after the host creates the dispatch and installs its context, so its first turn never depends on a prior readiness hook. It could not: a worker that has been asked nothing never reports that it finished anything, so an adapter that waited to be told the agent was idle would wait forever.

```bash
alera orchestration agent-spawn --agent codex --task <task-id> --title "Review Tests" --timeout-ms 90000
alera orchestration terminal-wait --terminal <handle> --for agent-ready --timeout-ms 30000
alera orchestration terminal-wait --terminal <handle> --for dispatch-accepted --timeout-ms 60000
```

The built-in registry supports `codex`, `claude`, `copilot`, `cursor`, `agy`, `opencode`, `opencode2`, `pi`, `amp`, `grok`, and `fx`, with matching default commands except Cursor, which launches `cursor-agent`. `agent-spawn --command` overrides the default without changing the agent type.

`agent-spawn --profile <name>` resolves the adapter and the command from the catalog instead. It replaces `--agent`, which becomes optional, and conflicts with `--agent` and `--command` so there is never a second source of truth for how a worker is launched. An unknown profile is refused by name. The dispatch records `agent_profile` and `agent_quota_group`, so `task-show` reports how each attempt was launched and fallback selection can read the attempt history.

For a task bound to a stage of an approved policy, the coordinator picks the profile itself: candidates are the stage's preferred profile followed by its fallbacks, minus everything already attempted for that task. Among what remains, a candidate whose quota group differs from the last attempt wins, because a fallback inside the same usage bucket buys nothing. An absent or unknown group counts as different, since the user never asserted that it shares a bucket. When nothing remains, behavior is unchanged: the task consumes startup budget and eventually stalls.

The trigger is the existing one. `fail_orchestration_startup` already returns a task to `ready`, and the next coordinator tick redispatches it with the next candidate. No cause detection is added: a startup failure is a startup failure, whether it came from an exhausted quota or a missing binary.

Startup states distinguish process creation, agent detection, agent readiness, submitted-but-unconfirmed dispatch, acceptance, failure, and stall. `agent-spawn --timeout-ms` controls how long the CLI waits for acceptance, up to the host acceptance limit of 90000 milliseconds. A failed spawn removes only the terminal created and owned by that attempt; reused terminals are never removed, and `--keep-on-failure` preserves a new terminal for diagnosis. Three startup/acceptance failures stall the task without consuming the execution circuit breaker.

For manual recovery, dispatch without `--inject`. The response prints a short bootstrap that tells the agent to accept and read `context`; add `--return-preamble` only when the full v2 preamble is needed. If hooks cannot describe an agent that the operator has independently confirmed is idle, `dispatch --inject --assume-agent codex` performs an audited adapter override.

## Worker Context And Lifecycle

The primary worker commands infer task, dispatch, coordinator, and assignee from the active terminal context:

```bash
alera orchestration dispatch-accept
alera orchestration --json context
alera orchestration heartbeat --phase reviewing
alera orchestration escalate --subject "Blocked" --body "Missing credentials"
alera orchestration complete --summary "Review complete" --completion-kind success --artifacts '[]' --files-modified "path/a" --validation '[]'
```

`context` returns the effective task spec for the current dispatch. For coordinator-created Codex workers, the host removes the internal `allow-stale-base: true` directive and includes the captured preflight result in `baseDrift` with `base`, `behind`, and `recentSubjects`; `baseDrift` is `null` when no drift was captured. Preflight metadata is matched to both task and dispatch IDs so a later dispatch cannot inherit stale context.

Completion validates structured results and atomically commits task/dispatch state, promotes DAG dependants, invalidates scoped operational messages, and returns lifecycle reconciliation in one response. A completed dispatch is accepted idempotently only when its task is also completed; dispatches closed by a decision gate reject late completion. `worker-done --task --dispatch --summary` is the explicit idempotent recovery form. Generic `send --type worker_done` and arbitrary `task-update --status` are rejected.

The only supported completion acknowledgement policy is currently `return-immediately`. The host rejects `wait-for-ack` and `keep-agent-idle` until those policies have distinct runtime state and acknowledgement semantics; terminal reuse remains independently controlled by `--terminal-policy`. `close-on-success` terminates the PTY, removes its persisted worker tab, and notifies connected clients.

Required result fields are `summary`, `completionKind`, `artifacts`, `filesModified`, and `validation`. A task can additionally carry a result schema; pass schema-specific properties as a JSON object with `complete --result-extra '{"ticket":42}'` or `worker-done --result-extra ...`. Reports belong in `artifacts`; only workspace source changes belong in `filesModified`.

Cancellation atomically marks the task and dispatch `cancelled`, closes pending decision gates, obsoletes pending operational messages, queues an urgent cooperative cancellation, and cancels unstarted DAG descendants. Completed or failed tasks reject late cancellation so successful descendants are not invalidated; repeated cancellation of an already-cancelled task is idempotent. Only the owning coordinator can cancel normally; `task-cancel --force` is the audited administrative recovery path. Dispatch interruption has the same ownership rule and requires `dispatch-interrupt --force` for administrative recovery. Use an explicit terminal/dispatch interrupt or termination only when cooperative cancellation does not stop the worker.

## Liveness And Messages

Runtime activity combines agent hooks, PTY output, and context-aware worker commands into dispatch and run-level `lastActivityAt`. The default accepted-dispatch lease is ten minutes. Expiry marks the task and dispatch `stalled`; stalled work continues occupying a concurrency slot because the worker may still be active, and Alera does not automatically redispatch potentially duplicated work. Recover with:

```bash
alera orchestration task-recover --id <task-id> --status ready --reason "Worker inspected and stopped"
```

When the run has an approved policy, its `stallPolicy` decides what happens next. `wait` is the historical behavior and stays the default for runs without a policy. `ask`, the default under a policy, opens a decision gate on the stalled task carrying the last activity time, the profile in use, and a tail of the terminal output; resolving it either interrupts the dispatch and returns the task to `ready` so fallback selection picks the next profile, refreshes the lease and resumes waiting, or cancels the task. `auto-failover` takes the kill-then-respawn branch without asking.

A stall gate is deliberately not an ordinary decision gate. `create_orchestration_gate` requires a live task and closes the active dispatch; here the worker may still be running, so `create_orchestration_stall_gate` accepts a `stalled` task and leaves both the task and the dispatch untouched. `coordinator_assert_gate_blocks` skips stalled tasks for the same reason. Failover is always confirm, kill, then respawn: the interrupt is sent before the task returns to `ready` so the old worker cannot keep writing to the worktree its replacement will use.

Operational messages carry task/dispatch/run/workspace scope and may expire. Completing, failing, cancelling, or superseding a dispatch marks its queued operational messages obsolete. Inbox and outbox responses refresh and expose queued, delivered, read, expired, and obsolete state.

Message admission is bounded at the storage boundary: handles and thread IDs are limited to 512 UTF-8 bytes, subjects to 256 bytes, lifecycle bodies to 8 KiB, and general bodies and serialized payloads to 64 KiB. Prompt injection truncates each body to 4 KiB and a complete batch to 16 KiB; omitted content remains available through `alera orchestration inbox`.

PTY input and durable output use bounded asynchronous queues. A blocked terminal writer cannot stall the host actor or unrelated terminals, and delivery is acknowledged only after the queued paste and optional submit complete. Absolute output cursors remain monotonic when retained scrollback is trimmed and when an exited session is reminted.

Wait commands return exit 0 for normal timeouts with `{ "outcome": "timeout", "waitedMs": ... }`; message waits also include `items: []`. Usage, transport, and runtime failures remain non-zero errors.

Terminal and task waits are parked in the runtime host, not implemented as CLI polling. Their deadline handler performs a final durable-state check before returning timeout, so a transition at the boundary is not lost.

```bash
alera orchestration task-wait --task <task-id> --for completed,failed,stalled --timeout-ms 300000
alera terminal wait --terminal <handle> --for dispatch-accepted --timeout-ms 60000
```

## Observability And Terminal Diagnostics

```bash
alera orchestration status --id <run-id>
alera orchestration task-show --id <task-id>
alera orchestration terminal-show --handle <handle>
alera terminal list --workspace <workspace-id>
alera terminal show --handle <handle>
alera terminal read --handle <handle> --max-bytes 65536
alera terminal read --handle <handle> --cursor <nextCursor>
alera terminal write --handle <handle> --text "continue" --enter
alera terminal write --handle <handle> --stdin --submit
alera terminal prune --workspace <workspace-id>
alera terminal prune --workspace <workspace-id> --apply
```

`terminal write --enter` writes the content and sends carriage return in a second operation after the first write completes. `--submit` additionally wraps the content in bracketed paste for interactive TUIs. `terminal prune` is a dry run unless `--apply` is present and only targets stopped terminals in the selected workspace.

Terminal reads return raw retained bytes, lossy text, an absolute monotonic stream cursor, the current retained `baseCursor`, and a 64 KiB default limit. If a requested cursor predates retained scrollback, reading resumes at `baseCursor` with `truncated: true`. Reads do not apply heuristic secret redaction because that could hide authentication or trust prompts.

All CLI list commands use the collection envelope `{ "kind": "...", "items": [...], "filters": {...} }`. Orchestration responses retain semantic aliases during the protocol transition.

`workspace add --parent-workspace-id <id>` creates and links a child workspace atomically.

## Validation

- `cargo test -p alera-core --features runtime` covers store, DAG, ownership, startup budget, cancellation, leases, and run isolation.
- `cargo test -p alera-cli` covers CLI/RPC contracts, real PTY behavior, wait outcomes, delivery, adapters, and regression scenarios.
- Adapter command construction is deterministic across supported platforms. Codex and Claude are the required live smoke targets when their executables are available.

The agent-facing command guide is `skills/alera-orchestration/SKILL.md`.
