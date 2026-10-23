# Inter-Agent Orchestration

Alera orchestration is owned by the Rust runtime host. Runs, tasks, dispatches, messages, gates, run events and administrative audit events are persisted in the runtime SQLite database; all mutations pass through the authenticated host actor. This page covers the agent-side protocol: how a coordinator delegates, how a worker reports, and how messages and inbox questions reach agents. The run model a person follows and controls (plans, gates, timeline, isolation, cleanup, Activity) is in [runs](runs.md).

## Contract Versions

- Terminal-host protocol: 5.
- Orchestration protocol: 3.
- Dispatch preamble: 3.
- Installed orchestration skill contract: 4.
- Orchestration store schema (`orchestration.schemaVersion`): 3.

Contract v3 breaks compatibility on purpose. Removed verbs answer `Unknown orchestration request` and there are no hidden aliases. An installed skill older than the binary is reported as `outdated` by `alera skill status`. Opening a store from an earlier schema backs it up and resets orchestration state; see [upgrading to schema v3](runs.md#upgrading-to-schema-v3).

`alera version --json` reports the CLI build and expected contracts, then queries an already-running compatible runtime host for its actual build and contract versions. Cargo builds embed `ALERA_BUILD_COMMIT` when supplied and otherwise resolve the current Git commit at build time. Host fields are `null` and `runtimeHostAvailable` is `false` when no compatible host is reachable; the command never invents host equality from the CLI build.

Runtime-host features are negotiated additively. Run and plan commands require `runsV1`, recipe commands `recipesV1`, terminal inspection and prune `orchestrationTerminalInspectionV1`, waits `orchestrationWaitV1`, the agent profile catalog `orchestrationAgentProfilesV1`, inbox questions `inboxV1`, `--deliver` on `alera inbox ask` `inboxV2`, and deferred Enter/submit `terminalDeferredInputV1`. The CLI asks for a host restart instead of sending an unsupported request.

## Runs And Ownership

Runs and tasks carry `workspaceId`, `runId`, `coordinatorHandle` and `assigneeHandle`. Multiple workspaces can coordinate concurrently, but a workspace holds at most one unfinished run. Creating a task for an existing run requires the same workspace and coordinator, and dispatches require the target terminal to belong to the task workspace.

Coordinator authority resolves from the run or task, never from whichever terminal calls a command. Cancelling runs, interrupting dispatches, recovering tasks, cancelling tasks and transferring ownership require the current coordinator or an audited `--force` action with a reason. A task attached to a run cannot transfer on its own; transfer the run so its tasks, active dispatches and in-memory coordinator stay aligned.

There are two ways to get a run:

- `alera orchestration run new` (or New Run in Activity) creates a planned run whose coordinator agent proposes the plan; see [runs](runs.md#lifecycle).
- `alera orchestration delegate` without `--run` adds the task to the caller's delegated shared run in the workspace, or starts one. Such a run has no coordinator loop; the 30 second lease sweep completes it once every task has finished. A workspace already held by another run keeps the task outside any run.

## Delegation

`delegate` is the only way a coordinator starts work. It creates the task, starts the chosen Agent Profile in a new terminal (or hands the task to an agent already running with `--terminal <handle>`), delivers the bootstrap, and waits until the agent is ready.

```bash
alera orchestration --json delegate --profile "Codex Sol" --spec "Review automated test coverage"
alera orchestration --json delegate --profile "Codex Sol" --spec "Implement the API" --new-workspace
alera orchestration --json delegate --profile "Opus" --spec-file brief.md --terminal <handle>
alera orchestration --json delegate --profile "Codex Sol" --spec "Write docs" --run <run-id> --stage docs --depends-on <task-id>,<task-id>
alera orchestration --json delegate --profile "Codex Sol" --spec "Fix the bug" --contract '<contract JSON>' --contract-inputs '<input JSON>'
```

- `--workspace` defaults from `ALERA_WORKSPACE_ID`; `--new-workspace` creates a child worktree first and infers project, source branch and parent from it or `--from-workspace`. `alera orchestration current` shows the inferred workspace and terminal.
- `--run` joins a run you coordinate, `--stage` binds the task to a stage of that run's plan, and `--depends-on` makes it wait for other tasks.
- `--contract` and `--contract-inputs` freeze a [role contract](orchestration-role-contracts.md) on the task.
- `--timeout-ms` (default and maximum 180000) bounds the wait for `agent-ready`; a failure reports "agent did not become ready". A failed delegation removes only a terminal it created; a reused terminal is never removed, and `--keep-on-failure` keeps a new terminal for diagnosis. A failed delegation can leave the created workspace and task, so inspect them before retrying.

Every adapter receives a short bootstrap after the host creates the dispatch and installs its context, so the first turn never depends on a prior readiness hook. It could not: a worker that has been asked nothing never reports that it finished anything.

Startup states, reported by `terminal show` and on dispatches: `process_started`, `agent_detected` and `agent_ready` (agent presence decides while the dispatch awaits its first worker command), then `accepted`, `completed`, `stalled` or `failed`; a dispatch without injection is `awaiting_manual_delivery`. `terminal wait --for` takes `process-started`, `agent-detected`, `agent-ready`, or `dispatch-accepted`, which now means the worker's first command was received.

```bash
alera orchestration terminal wait --terminal <handle> --for agent-ready --timeout-ms 60000
alera orchestration task wait --id <task-id> --for completed,failed,stalled --timeout-ms 300000
```

For a task bound to a stage, the runtime picks the profile: the stage's preferred profile followed by its fallbacks, minus every profile already attempted for that task. Among what remains, a candidate whose quota group differs from the last attempt wins, because a fallback inside the same usage bucket buys nothing. An absent or unknown group counts as different. A startup failure returns the task to `ready` and the next pass redispatches it with the next candidate; no cause detection is attempted. Three startup failures stall the task without consuming the execution circuit breaker.

## Worker Protocol

A worker has no accept step and no heartbeat. The primary commands infer task, dispatch, coordinator and assignee from the terminal's dispatch context:

```bash
alera orchestration --json context
alera orchestration complete --summary "What was done and what remains"
alera orchestration escalate --subject "Blocked" --body "Missing credentials"
alera orchestration ask --to <coordinator-handle> --question "Which branch?"
```

**Implicit acceptance.** The first `context`, `ask`, `escalate` or `complete` from the dispatch's terminal accepts it: a dispatch in `awaiting_acceptance` becomes accepted and the spawn's ownership metadata is consumed. Later worker commands renew the lease.

**Liveness without heartbeat.** Agent hooks, PTY output and worker commands feed the dispatch's and run's `lastActivityAt`. A host-wide sweep runs every 30 seconds on the agent presence tick, independent of any coordinator loop:

1. A dispatch still awaiting its first worker command after 180 seconds fails its startup only when its terminal session is not running or has no agent presence. An agent that was detected but has not run a command yet is left to the activity lease.
2. An accepted dispatch with no activity for 10 minutes becomes `stalled`, and the run's stall policy applies (a `stall` gate by default; see [runs](runs.md#gates)). A stalled task keeps its concurrency slot because the worker may still be running, and Alera never redispatches it silently.
3. Resolved stall gates are carried out.

A stall is a suspicion, not a verdict: any later output, hook or worker command revives the dispatch and its task to `dispatched` and resolves the pending stall gate as `resumed`, and `complete` works from `stalled`.

**Minimal completion.** `complete` records the result exactly once. Only `--summary` (non-empty) is required; `--kind` defaults to `success`. `--files`, `--artifacts`, `--validation` and `--result-extra` are optional and stored as empty arrays when omitted; they are validated only when the task has a role contract or a result schema. A completed dispatch accepts the same completion idempotently; dispatches closed by a decision gate reject late completion. `--kind failure` consumes the task's failure budget and may return it to ready. After completing, the worker ends its turn and leaves the terminal for reuse. Generic `send --type` messages and arbitrary task status edits cannot complete a task.

`context` returns the effective task spec. For coordinator-created Codex workers the host removes the internal `allow-stale-base: true` directive and reports the captured preflight in `baseDrift` (`base`, `behind`, `recentSubjects`), or `null`. Preflight metadata matches both task and dispatch ids so a later dispatch cannot inherit stale context. In an isolated run, `context` answers from the attempt's launch context.

The v3 preamble (`dispatch_preamble.rs`) is a short bootstrap: run `alera orchestration --json context`, do the task, then `alera orchestration complete --summary "..."`; ask with `ask`, report blockers with `escalate`. Its contract section lists `--json context`, `complete --summary` with the optional flags, `ask`, `escalate`, `check` and `messages`, and says to complete exactly once and then end the turn.

**Cancellation.** Cancelling a task marks it and its dispatch `cancelled`, closes its pending decision gates, obsoletes its pending operational messages, queues an urgent cooperative cancellation and cancels unstarted descendants. Completed or failed tasks reject late cancellation; repeating a cancellation is idempotent. Use `dispatch interrupt` or terminal termination only when cooperative cancellation does not stop the worker.

```bash
alera orchestration task cancel --id <task-id> --reason "No longer needed"
alera orchestration task recover --id <task-id> --status ready --reason "Worker inspected and stopped"
alera orchestration dispatch interrupt --id <dispatch-id> --reason "Wrong approach"
alera orchestration transfer-coordinator --run <run-id> --to <handle> --force --reason "Coordinator crashed"
```

## Gates

Gates live in one table for every kind (`decision`, `stall`, `plan`, `stage`); [runs](runs.md#gates) describes their options and effects. From the agent side:

- `alera orchestration gate create --task <id> --question "..." [--options '["A","B"]']` opens a decision gate that closes the task's dispatch and blocks the task until a person answers.
- `gate list --run <id>` reads `runs.gates`; without `--run` it reads `orchestration.gateList`, the decision gates of tasks outside runs.
- `gate resolve --id <id> --decision <option> [--reason] [--tasks] [--expected-digest]` calls `runs.resolveGate`. A gate with options accepts only one of them. `--expected-digest` is required for a gate that has an `evidenceDigest` (`gate_stale` otherwise), and plan, stage, and stall gates are refused from the run's own terminals (`gate_not_resolvable`).

A coordinator's loop turns only an explicit `send --type decision_gate` naming a task into a gate; a worker's `ask` is a `question` the coordinator agent answers with `check` and `reply`. Gate pushes carry `{kind: "decisionGate", gateId, gateKind, runId, taskId?}`, titled "Plan Needs Approval" for plan gates and "Decision Needed" otherwise; run-scoped gates are located at the run's coordinator terminal and workspace.

## Messages And Delivery

```bash
alera orchestration send --to <handle|@group> --subject "Status" --body "Details" [--delivery now|turn-end]
alera orchestration check [--wait --types escalation,question --timeout-ms 300000]
alera orchestration messages --terminal <handle> --direction inbox
alera orchestration ask --to <handle> --question "..." [--options "A,B"] [--no-wait] [--delivery now|turn-end]
alera orchestration reply --id <message-id> --body "..."
```

`messages` (formerly `orchestration inbox`, RPC `orchestration.messages`) lists recent messages, optionally for one terminal and direction. Message types are `status`, `dispatch`, `merge_ready`, `escalation`, `handoff`, `decision_gate` and `question`. Every message carries `delivery: now | turnEnd`.

| Producer | Default delivery |
| --- | --- |
| `inbox.ask` (desktop, mobile, `alera inbox ask`) | `now` |
| `orchestration.ask` | `now` |
| `send`, `reply`, escalations, cancellations | `turnEnd` |

When a message is sent the host decides, per recipient (`deliver_after_send`):

1. An active coordinator is never pasted into; it reads with `check` (`check`).
2. A terminal with no running session or no agent presence gets nothing (`unavailable`).
3. An idle agent (non-inferred `done`) receives everything queued for it (`pasted_now`).
4. An agent whose presence is `working`, whose adapter has `accepts_queued_input`, and that has no delivery in flight receives only its `delivery = now` messages, through the same bracketed paste and deferred Enter (`pasted_now`).
5. Otherwise the message waits for the turn to end (`queued_at_turn_end`). An agent that is `waiting` or `blocked` never gets a mid-turn paste, because an Enter could answer its prompt.

Responses report that outcome as `deliveryMode` (`pasted_now`, `queued_at_turn_end`, `check`, `unavailable`): `send` per recipient in `deliveries` (and top-level for exactly one non-inbox recipient), `reply`, `ask --no-wait`, `inbox.ask`, every inbox thread, and every `inbox.targets` item, where it describes what `now` would do right now next to `acceptsQueuedInput`.

`accepts_queued_input` is declared per adapter in `agent_registry.rs` and pinned by `only_verified_agents_accept_input_queued_mid_turn`. Today every adapter is `false`, so a `now` message to a working agent waits for its turn to end; `claude` and `codex` are the first candidates. Before setting it for an adapter, verify it by hand against the installed CLI, twice in a row:

1. Start the agent in an Alera tab and give it a long turn, for example running `sleep 90` through its shell tool.
2. While it works, run `alera orchestration send --to <handle> --delivery now --body "reply with the word pong"`.
3. Confirm the TUI shows the message as queued input, processes it as the next turn after the current one, and does not corrupt the output of the running turn.

Message admission is bounded at the storage boundary: handles and thread ids at most 512 UTF-8 bytes, subjects 256 bytes, bodies and serialized payloads 64 KiB. Operational messages carry task, dispatch, run and workspace scope and may expire; completing, failing, cancelling or superseding a dispatch marks its queued operational messages obsolete. Prompt injection truncates each body to 4 KiB and a batch to 16 KiB; truncation and omission hints point at `alera orchestration messages --terminal <handle>`.

Delivered messages arrive as banners:

```text
[Alera] Question from ext:ci-review via Alera desktop, id q_123
<body>
Reply: alera orchestration reply --id q_123 --body "..." (the sender cannot read this terminal)
```

Messages between agents start with `[Alera] Message from <handle>, id <id>` (`Question from` for a `question`), add a `Subject:` line when it differs from the body and a payload line, and end with the reply line. Text left in the terminal never reaches the sender, and the last assistant message is never captured as an answer.

`ask` waits for the answer (`--timeout-ms`, default 120000). A worker's question goes to its dispatch's current coordinator, even after a transfer, as a `question` with high priority. `--no-wait` prints the question id at once; the answer is pasted on the asker's next turn like any message, or read earlier with `alera inbox wait --question <id>`, which consumes it so it is not pasted again.

PTY input and durable output use bounded asynchronous queues. A blocked terminal writer cannot stall the host actor or unrelated terminals, and delivery is acknowledged only after the queued paste and optional submit complete. Absolute output cursors remain monotonic when scrollback is trimmed and when an exited session is reminted.

Wait commands return exit 0 for normal timeouts with `{ "outcome": "timeout", "waitedMs": ... }`; message waits also include `items: []`. Waits are parked in the runtime host, not implemented as CLI polling, and their deadline handler checks durable state once more before returning timeout.

## Inbox

The inbox lets a caller that is not an Alera terminal ask an agent a question and read the answer later: another agent session, a script, an integration, or the desktop and mobile apps. The caller writes from an inbox address, `ext:<name>` (lowercase letters, digits, dots, underscores and hyphens, at most 63 characters after the prefix). No terminal is created for the asker and no credential is issued per inbox: the runtime host token and the paired-device session are the only authorization.

```bash
export ALERA_EXTERNAL_INBOX=ext:ci-review
alera inbox targets --workspace <workspace-id>
q=$(alera inbox --json ask --workspace <workspace-id> --agent claude --body "Which tests cover login?" | jq -r .questionId)
alera inbox ask --thread "$q" --body "And the logout path?" --deliver turn-end
alera inbox --json wait --question "$q" --timeout 30m
alera inbox threads
alera inbox show --question "$q"
alera inbox cancel --question "$q"
alera inbox purge --inbox ext:ci-review --confirm
```

A question is an `orchestrationMessages` row of type `question` from the inbox to an agent terminal, high priority, with the recipient's workspace and no task, dispatch or run scope, so finishing a dispatch never makes it obsolete. It is delivered with `now` unless the caller chose `turnEnd` (`--deliver turn-end` on the CLI, Deliver in the apps); `--deliver` is sent only when given and needs `inboxV2`.

Answers are explicit. `orchestration.reply` records `reply_to_id`, and a question counts as answered only when a reply from its recipient names it. A message the agent sends to the inbox in the same thread without that reference is shown as a message, not an answer. Agents may also write first: `send --to ext:<name>` without `--thread-id` opens a thread (listed with `inbox` = the address and `recipient` = the agent, status `answered` until the inbox asks), and `--thread-id` continues any thread between that inbox and the agent in either direction; a thread id from another pair is refused with `inbox_thread_mismatch`. Follow-ups from the inbox continue a thread with the same recipient. An `ext:` address cannot send through `orchestration.send` or `ask`, be dispatched to, coordinate, own a task or spawn, and a message an inbox received cannot be replied to as that inbox; follow-ups always go through `inbox.ask`, so expiry and the pending limit apply.

The derived question status is, in precedence order, `cancelled`, `answered`, `expired`, `delivered` and `pending`. There is no `received`: a coordinator that reads a question with `check` counts as delivered, and clients map a `received` from an older host to `delivered`. `external_meta` records the surface that asked (`cli`, `desktop`, `mobile` with the device, or an MCP client), decided by the connection rather than the payload, a snapshot of the target agent, tab and workspace, the delivery mode, and the cancellation.

A question that has not reached the agent expires after 5 hours by default (`--expires-in`, 1 minute to 7 days) and is never pasted after that; a delivered question keeps waiting for its reply. A recipient holds at most 100 undelivered inbox questions; one more is refused with `inbox_pending_limit` ("This agent already has 100 questions waiting. Wait for it to read them or cancel some."). Inbox threads are deleted 7 days after their last activity unless a question in them still waits for delivery. Only a question that has not been pasted, read or answered can be cancelled; delivery is best effort, so a batch being pasted cannot be withdrawn, and a batch larger than one paste leaves the remainder queued for the next turn.

`inbox.wait` parks a request for one question, or for anything new addressed to an inbox after a cursor, wakes on replies, cancellation and purge, and reads the store once more at the deadline before reporting `timeout`. The host ceiling is 10 minutes per request; `alera inbox wait` chains requests up to `--timeout`, retries across a host restart, and exits 2 on timeout. Every change to an inbox row moves a durable revision in the same transaction, announced to every authenticated client as `inboxChanged {revision}`. A reply to an inbox sends a push in the existing `attention` category with a generic title, the workspace and ids only; push payloads never carry the question or the reply.

The host advertises `inboxV1` and `inboxV2` (delivery choice, `deliveryMode`, no `received`) for local clients and in `mobile.hello`. Paired phones and relay clients may call exactly `inbox.summary`, `inbox.threads`, `inbox.thread`, `inbox.targets`, `inbox.ask`, `inbox.cancel`, `inbox.markRead` and `inbox.purge`. `inbox.wait` stays local because the apps use the event, `inbox.conversations` and `inbox.conversation` are no longer phone-allowed, and no `orchestration.*` verb is on the phone allowlist; the orchestration router applies that allowlist itself because it runs before the generic request handler. A satellite forwards the inbox verbs to its hub by name, so the inbox of a remote terminal is the hub's inbox. The desktop and mobile apps ask from the shared `ext:user` inbox from **Activity > Questions**, and the read state of a reply is shared between devices.

### Conversations Between Agents

`inbox.conversations` and `inbox.conversation` (`alera inbox conversations|conversation`) stay as a read-only view for local clients, the CLI and MCP: `status`, `handoff`, `merge_ready` and `decision_gate` messages between terminals grouped by thread; viewing never marks a message read. The desktop and mobile apps no longer show them; a run's messages appear in its [timeline](runs.md#timeline), which refreshes on `conversationsChanged`. Agent conversations are deleted 7 days after their last activity unless a message in them is still queued or belongs to an unfinished task or dispatch.

## CLI

`alera orchestration` has 20 entries:

| Group | Commands |
| --- | --- |
| Coordinator | `delegate`, `run new\|list\|show\|timeline\|cancel\|pause\|resume\|replan\|retry\|resources\|integrations\|cleanup`, `plan context\|propose\|show`, `gate list\|show\|resolve\|create` |
| Worker and messages | `context`, `complete`, `escalate`, `ask`, `reply`, `send`, `check`, `messages` |
| Tasks and terminals | `task show\|wait\|cancel\|recover`, `transfer-coordinator`, `dispatch show\|interrupt`, `terminal list\|show\|wait\|prune`, `agent-profiles`, `current`, `reset` |
| Recipes | `recipe list\|show\|validate\|save-personal\|export` |

Run mutations send a fresh `requestId` (`run new --request-id` sets it) and, when an MCP tool runs the CLI, `externalOrigin`, so the actor is `mcp:<client>`. Control commands read `controlSequence` from `runs.snapshot` unless `--expected-sequence` is given. `reset` clears orchestration state (`--all` by default, or `--tasks`, `--messages`) and keeps Agent Profiles and recipes.

Removed in v3: `dispatch-accept`, `heartbeat`, `worker-done`, `worker-help`, `run-policy-*`, `task-create`, `agent-spawn`, `task-list`, manual `dispatch`, `board`, `run-snapshot`, `task-inspect`, the loop-starting `run`, `run-list`, `run-show`, `run-stop`, `status`, the flat `task-*`, `gate-*`, `terminal-*`, `dispatch-*` and `plan-*` verbs, `inbox` (now `messages`), and the workflow groups `recipes`, `plans`, `proposals`, `execution`, `cleanup` and `workspaces`. The RPCs `orchestration.dispatchAccept`, `heartbeat`, `workerDone`, `workerHelp`, `runPolicyPropose`, `runPolicyApprove`, `runPolicyReject`, `runPolicyShow`, `inbox`, `boardSnapshot`, `runSnapshot`, `taskInspection`, `gateResolve` and every `workflows.*` verb are gone; the RPCs `orchestration.run`, `runStop`, `runList`, `runShow`, `status`, `taskList`, `taskCreate`, `taskCreateContracted`, `agentSpawn` and `dispatch` remain for the runtime and `delegate`, without CLI commands of their own.

## Agent Profile Catalog

Tasks may carry [versioned role contracts](orchestration-role-contracts.md), which freeze portable instructions, inputs and completion requirements without changing profile launch configuration. [Recipes](recipes.md) embed contracts for isolated runs.

An agent profile is a user-declared launch configuration a run can dispatch to. Each profile carries a unique name, an adapter type from the built-in registry, a launch mode, a custom prompt, a free-text description used as a routing signal, and an optional quota group. Profiles are user configuration, not run state: they live in the runtime schema next to `sshTargets`, so resetting orchestration state never destroys them.

```bash
alera orchestration --json agent-profiles
```

The coordinator-facing `orchestration agent-profiles` surface is read-only by design. A coordinator discovers what it may dispatch to and what each option is good for, while the user manages the approved catalog through Settings -> Agent Profiles or the top-level administrative CLI:

```bash
alera agent-profile --json list
alera agent-profile create --name "Codex Sol" --agent-type codex --launch-mode command --command "codex --search"
alera agent-profile create --name "Managed Codex" --agent-type codex --launch-mode managed --managed-config-file profile.json
alera agent-profile update --profile-name "Codex Sol" --description "Backend implementation"
alera agent-profile removal-impact --profile-name "Codex Sol"
alera agent-profile remove --profile-name "Codex Sol" --confirm
```

`show`, `update`, `removal-impact`, and `remove` accept either `--profile-id` or the case-insensitive unique `--profile-name`. Updates patch only the supplied fields, fetch the current revision by default, and accept `--expected-revision` when a script must pin the version it observed. Managed configuration may be supplied inline with `--managed-config`, from a file, or from standard input. Changing `--agent-type` on an existing Managed profile requires an explicit new managed configuration so adapter-specific settings are never discarded silently. A new setting that reduces agent protections requires `--confirm-reduced-protections`, and removal always performs the impact check before asking the host to delete.

Reordering replaces the complete catalog order and therefore requires every stable profile id exactly once:

```bash
alera agent-profile reorder --id <second-profile-id> --id <first-profile-id>
```

A coordinator picks from a closed list the user approved instead of inventing launch commands: `delegate` always resolves its adapter and command from a catalog profile, and an unknown profile is refused by name. The dispatch records `agent_profile` and `agent_quota_group`, so `task show` reports how each attempt was launched and fallback selection can read the attempt history.

The adapter type is required because the registry is more than a command: it decides how the host detects readiness, injects the dispatch preamble, forces submission, and whether a working agent accepts queued input. The built-in registry supports `codex`, `claude`, `copilot`, `cursor`, `agy`, `opencode`, `pi`, `amp`, `grok`, and `fx`, with matching default commands except Cursor, which launches `cursor-agent`. The host rejects a profile whose adapter is not in `AGENT_ADAPTERS`. `opencode` covers OpenCode v1 and OpenCode 2; the host reads the retired `opencode2` key as `opencode` and picks the launch line from the installed generation.

`alera agent-profile launch --profile <name> --prompt "..."` launches that catalog entry in an existing workspace without creating an orchestration task. `alera workspace start --profile <name> --prompt "..."` creates a managed worktree and then launches it, which is the CLI form of New Workspace from Prompt.

Before creating a worker tab, the host persists `agentProfileLaunchV1`: the resolved profile identity and concrete OCC revision, adapter, launch mode, effective Command line or Managed executable and argv, local target/platform, and initial-delivery policy. Recovery launches from that immutable snapshot and does not resolve the mutable profile again, so later profile edits cannot change an existing worker. New profiles start at revision `0`, updates advance that revision, and every launch captures the exact revision it resolved. Command lines remain opaque interactive-shell input; the host never splits or reparses them. The snapshot excludes environment and provider session state. Tabs without a snapshot continue through the legacy readers.

Terminals started for a run carry the host-owned tab keys `runId` (coordinator and workers) and `runTaskId` (workers), protected like `agentNativeSessionId`; see [runs](runs.md#runtime-api).

When a supported agent hook reports a native conversation, session, or thread identifier, the host stores it on that tab as `agentNativeSessionId` plus the adapter that produced it. This includes a plain terminal where the user typed the agent. Client tab updates cannot replace those fields. The next remint uses that id with the adapter's resume shape (`codex resume <id>`, `claude --resume <id>`, and the equivalent flag or subcommand for the other spawnable agents) and does not replay the original prompt. A tab without an Agent Profile snapshot or `initialCommand` synthesizes the adapter default command plus those resume tokens. Missing, empty, parent-session, or unusable ids leave the existing launch unchanged. Desktop and mobile both see the stored id on the projected tab; Mobile-specific resume UI is not part of this path. A Claude session launched through CCS also stores `agentNativeCcsProfile` from `CLAUDE_CONFIG_DIR` (`.../instances/<profile>`), so resume is `ccs <profile> --resume <id> ...` even when the user started Claude through a shell alias. Default Claude is not a CCS instance.

For delivery policies that replay on PTY restart, the tab separately retains the initial bootstrap until the tab is deleted. `pendingAgentPrompt` is a consumable per-PTY copy: the first matching ready event spends it, while a newly minted PTY rearms it from the retained bootstrap. Attaching again to the same PTY does not rearm it. Both bootstrap fields are removed from tab protocol projections and are used only for initial terminal delivery; they are not provider-resume data. A stored native session id is provider-resume data and skips that bootstrap when the remint can resume.

Managed mode exposes the supported model, effort, persona, permission, sandbox, and trust controls for the selected adapter. Missing options deliberately defer to that agent's own configuration. The host validates the structured configuration and quotes the resulting executable and arguments for the actual platform shell only when the terminal is spawned. Command mode remains available for advanced or unsupported CLI options; its value must be the interactive form the adapter expects, because a one-shot mode exits before the worker can complete its task. Existing profiles are migrated as Command profiles without changing their behavior.

A managed Codex profile carries a second effort setting, `planModeEffort`, which becomes `-c plan_mode_reasoning_effort=<value>`. It governs only how hard Codex thinks while it is in plan mode, and the profile cannot put it there: Codex 0.146 has no flag or config key for the startup collaboration mode, which is entered with Shift+Tab or `/plan` in the TUI (`collaboration_mode` is an app-server per-turn parameter, not a config file key). The editor says so on the control rather than implying the profile selects the mode. The upstream request is openai/codex#13942.

A managed Claude profile can also pass `--allow-dangerously-skip-permissions` through `allowSkipPermissions`. That flag only makes bypass reachable inside the session; `permissionMode: bypassPermissions` is what starts there, and the two are independent on purpose. It still counts as a reduced-protection marker, so turning it on asks for confirmation before the profile is saved.

A managed Claude profile may also carry an optional `ccsProfile`. When it is set, the launch replaces the executable with `ccs` and passes the profile as its first positional argument, followed by the same Claude flags, because that is the switcher's own contract (`ccs <profile> [claude-args...]`). The value must be a single name that does not start with a dash: it is positional, so a dash-prefixed value would be read as an option of the switcher itself. Only the Claude adapter accepts the key; the host rejects it anywhere else. Native session resume keeps that profile in front of `--resume`, so a remint is `ccs <profile> --resume <id> [claude-args...]` rather than handing `--resume` to the switcher. `ccs` points `CLAUDE_CONFIG_DIR` at the account instance directory, whose `settings.json` is a symlink chain to `~/.claude/settings.json`. That user file is where Alera installs the agent-status hooks, because it is the only settings source such a session reads; see [`architecture.md`](architecture.md) for why the instance directory cannot hold them and how Grok is kept from running them.

Command mode also has to say where the dispatched prompt goes, because the user writes the whole launch line there. That follows the adapter's `startup_prompt`, which names the shape that agent's own CLI accepts for starting interactively with a prompt already submitted: a positional argument after the option terminator for Codex, Claude, Cursor and Grok Build; a bare positional for `pi`, which rejects the terminator and gets a leading space instead when the prompt opens with a dash; a single `--interactive=`, `--prompt-interactive=` or `--prompt=` token for Copilot, Antigravity and OpenCode; standard input for Amp; and a terminal paste after the first semantic ready event for fx. The editor states which one applies and previews the resulting line wherever the prompt reaches the command line.

The profile's Custom Prompt is added after the prompt supplied by New Workspace or `delegate`, when it is non-empty. The project's `new_workspace.prompt_append` is added last, so every delivered prompt has the order user prompt, profile instructions, then project instructions, with blank lines between non-empty sections.

The quota group declares which profiles drain the same usage bucket. Alera never measures, predicts, or verifies quota here; the grouping is an assertion the user makes, and its only purpose is to let a fallback prefer a candidate from a different bucket.

The app manages the catalog with `agentProfile.list`, `agentProfile.upsert`, and `agentProfile.remove`, applies successful mutations immediately, and reconciles them with the debounced `agentProfilesChanged` snapshot. Managed mode is advertised through the additive `orchestrationManagedAgentProfilesV1` capability and does not change the terminal host protocol version.

## Observability And Terminal Diagnostics

```bash
alera orchestration --json run show --run <run-id>
alera orchestration --json task show --id <task-id>
alera orchestration terminal show --handle <handle>
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

All CLI list commands use the collection envelope `{ "kind": "...", "items": [...], "filters": {...} }`.

`workspace add --parent-workspace-id <id>` creates and links a child workspace atomically.

## Validation

- `cargo test -p alera-core --features runtime` covers the store, the v3 reset, DAG, ownership, startup budget, cancellation, leases, gates (`orchestration_gate_store_tests`) and run isolation.
- `cargo test -p alera-cli` covers CLI/RPC contracts, real PTY behavior, wait outcomes, delivery (`inbox_delivery_tests`), the lease sweep (`orchestration_lease_sweep_tests`), adapters, and regression scenarios.
- `inbox_store_tests`, `inbox_listing_tests` and `conversation_store_tests` cover the inbox store; `inbox_requests_tests`, `conversation_requests_tests`, `orchestration_mobile_access_tests` and `mobile_gateway_surface_runs_tests` drive the real dispatcher with local, desktop, paired-phone, relay and unauthenticated clients.
- Adapter command construction is deterministic across supported platforms. Codex and Claude are the required live smoke targets when their executables are available.

The agent-facing command guide is `skills/alera-orchestration/SKILL.md`.
