# Runs

A run is the unit of coordinated agent work. The Rust runtime host owns it: a coordinator agent plans it, workers carry out its tasks, and every decision a person owes it is a gate. Runs, plans, tasks, gates, the timeline and retained resources live in the runtime SQLite database, and every mutation passes through the authenticated host actor. The agent-side protocol (dispatch, `context`, `complete`, messages) is described in [orchestration](orchestration.md); Git isolation and integration in [runs integration](runs-integration.md); templates in [recipes](recipes.md).

## Model

```text
Run (shared | isolated)
  Plan          revisions; approval is opt-in
  Tasks         one dispatch per attempt, to a worker terminal
  Gates         decision | stall | plan | stage
  Timeline      run events plus messages between the run's agents
  Resources     attempt worktrees, branches, integration, cleanup
```

A run belongs to one workspace, and a workspace holds at most one unfinished run (`planning`, `awaitingApproval`, `running`, `paused`, or a `cancelled` run whose targets have not settled). Authority comes from the run, never from whichever terminal calls a command.

| Isolation | Behaviour |
| --- | --- |
| `isolated` (default for `runs.create`) | A [recipe](recipes.md) fixes the stages and roles. Every task attempt runs in its own worktree on an `alera/runs/<uuid>` branch, and results integrate serially as local squash commits into the run's integration workspace. Dependents wait for integration, not for the worker's report. See [runs integration](runs-integration.md). |
| `shared` | Workers share the run's workspace. The coordinator declares stages with a preferred profile and ordered fallbacks; there is no recipe and no integration step. `delegate` without `--run` creates or joins a shared run. |

## Lifecycle

| Status | Meaning |
| --- | --- |
| `planning` | The coordinator is preparing a plan. Nothing is scheduled. |
| `awaitingApproval` | A plan gate is pending. Nothing is scheduled. |
| `running` | The scheduler dispatches ready tasks. |
| `paused` | No new dispatches. `pausedBy` is `user` (Pause) or `runtime` (a due stage gate). Dispatched workers keep going. |
| `completed` | Isolated: every task integrated with evidence and every gated stage approved. Shared: every task finished. |
| `failed` | Declared by the coordinator's convergence. |
| `cancelled` | Cancelled by a person, by the coordinator, or by a rejected plan. `completedAt` is stamped once every cancellation target has settled. |

1. `runs.create` freezes the recipe, the Agent Profiles and the source commit, inserts the run in `planning` with a reserved coordinator, and launches the coordinator terminal through the one-shot launch permit. A replayed `requestId` returns the first run and never launches a second coordinator. A launch failure sets `coordinatorState: attention` with the error.
2. The coordinator reads `alera orchestration --json plan context --run <id>` and submits `alera orchestration plan propose --run <id> --stdin`. A proposal becomes the next plan revision and materializes its tasks and stage gates in one transaction.
3. Without approval the run goes straight to `running` (recorded as `planApproved` by `runtime`). With approval a `plan` gate opens and the run waits in `awaitingApproval`. An isolated run requires approval for every revision once it was created with `approvalRequired`; a shared run only until a plan was approved once. A new proposal while a plan waits supersedes the pending gate and the unstarted tasks of the old revision.
4. While `running`, isolated runs advance through the scheduler pump and shared runs through the coordinator tick. When a stage gate becomes due, the runtime binds its evidence, pauses the run (`pausedBy: runtime`) and pushes the gate.
5. A person resolves gates, pauses, resumes, replans or cancels. Approving the last due gate resumes a runtime pause.
6. An isolated run that finished keeps its worktrees and branches until a reviewed cleanup.

An isolated run accepts proposals only in `planning` or `awaitingApproval`; a shared run also while `running` or `paused`. Startup recovery marks a `planning` run whose coordinator was reserved or started as coordinator attention; it never relaunches the coordinator on its own.

### Plans

Each revision is an immutable row in `runPlanRevisions`. An isolated revision is the compiled recipe plan (stages, roles, contracts, frozen profiles, tasks with `dependsOn`, `inputs` and optional `correctsTaskId`). A shared revision is `{version: 2, objective, stages, tasks, stallPolicy, maxConcurrent, digest}`. Task definitions of a plan revision are immutable; tasks added later with `delegate --stage` carry no plan revision and do not make a stage due.

Request Changes (on a plan or stage gate) and Replan (`runs.control replan`) need a reason. They insert a placeholder revision with the reason and the named tasks, cancel `pending`, `ready`, `blocked` and `failed` tasks, keep completed evidence, invalidate other pending gates, return the run to `planning`, and either message the coordinator (`status`, high priority, from `alera`) when its terminal is running or relaunch it on the same tab with the correction prompt. The response reports `coordinatorAction: message | relaunch | none`. A change request is refused while a task is `dispatched` or `stalled` (`run_has_active_work`) or an integration has not settled (`run_integration_pending`). The coordinator reads the request as `correction` in `plan context`.

## Gates

Every decision a run owes is one row in `runGates`, with `kind`, an optional `taskId`, `options`, a `status` of `pending`, `resolved`, `timeout` or `invalidated`, and the resolving actor.

| Kind | Scope | Options | Effect |
| --- | --- | --- | --- |
| `plan` | Run | `approve`, `requestChanges`, `reject` | Approve starts the run. Reject cancels it with the reason as `stopReason`. Request Changes replans. |
| `stage` | Run, one stage | `approve`, `requestChanges`, `reject` | Due once the stage and its prerequisite stages are complete (isolated: integrated with validated evidence and prerequisite gates approved). Approve resumes a runtime pause; reject cancels; Request Changes replans. Recipe stages with a `foundation` or `product` gate always need this decision, with or without plan approval. |
| `stall` | Task | `killAndFailover`, `keepWaiting`, `abortStage` | Opened when a worker stalls and the run's stall policy is `ask`. Kill And Failover interrupts the worker before the task returns to `ready`, so the next fallback profile is chosen; Keep Waiting refreshes the lease; Abort Stage cancels the stalled task. The task and dispatch stay untouched until then, because the worker may still be running. |
| `decision` | Task | The gate's own options, or free text when it has none | `gate create` blocks the task; resolving returns it to `ready`. |

A gate with options accepts only one of them (`gate_invalid_resolution`). A stage gate binds `evidenceDigest` and `integrationSha` when it becomes due; changed evidence invalidates it and a fresh, not-yet-due gate replaces it. `runs.resolveGate` must carry `expectedEvidenceDigest` for every gate that has an `evidenceDigest` (every plan gate, and a stage gate once due); a missing or different digest is refused with `gate_stale`, and the client refreshes and decides again. Plan, stage, and stall gates are a person's decisions: a CLI running in an Alera terminal sends that terminal as `callerTerminal`, and the runtime refuses those gates with `gate_not_resolvable` when the terminal coordinates the run, works on it, or created its tasks. Other conflict codes: `gate_not_found`, `gate_not_pending`, `gate_not_due`, `gate_invalid_kind`. A stall is resolved internally as `resumed` when the worker shows activity again; that value is never an option.

Plan, stage and stall gates are a person's decisions. The agent skills tell coordinators never to resolve them or approve their own plan, and the MCP catalog exposes `resolve_run_gate` only at the administrative access level.

No gate kind has a deadline: `runGates` has no expiry column, and the only `timeout` transition is a cancelled task's pending gates.

The stall policy (`ask` by default, `auto-failover`, `wait`) is stored on the run. `auto-failover` takes the kill-then-respawn branch without a gate; `wait` keeps the stalled task until someone recovers it. Failover is always interrupt first, then redispatch.

## Timeline

`runEvents` records what happened to a run, in the same transaction as the change. Each event carries an optional task, dispatch and gate id, the actor, a summary of at most 512 bytes and a JSON payload of at most 8 KiB. Every kind is written:

| Kinds | Written when |
| --- | --- |
| `created`, `coordinatorStarted`, `attention` | The run is created; its coordinator terminal starts, or fails to start (`attention` with the error) |
| `planProposed`, `planApproved`, `planRejected`, `changesRequested` | A plan revision is stored; it is approved (by a person, or by the runtime when no approval is required); rejected; or sent back with a reason |
| `taskCreated`, `attemptPrepared` | A plan materializes its tasks; an isolated attempt's worktree reaches `ready` (summary `Attempt <n>`, payload `workspaceId`, `attempt`, `branch`, `baseSha`) |
| `dispatched`, `accepted` | A task is handed to a terminal; the worker's first command accepts it (actor `agent`) |
| `escalation` | A worker escalates. The event names the escalation message (`payload.messageId`), and the timeline returns that message's route and body on the event instead of listing the message separately |
| `taskCompleted`, `taskFailed`, `taskStalled`, `taskCancelled` | A worker completes; a dispatch fails (`payload.willRetry` is false once the circuit breaker fails the task), startup fails, or a coordinator or recovery marks the task failed; the activity lease expires or startup failed a third time; a task, or a dependent of one, is cancelled |
| `gateOpened`, `gateResolved` | A decision, stall, plan or stage gate opens or is resolved (including a stall resolved as `resumed`) |
| `integrationStarted`, `integrated`, `conflict` | An isolated attempt's integration is reserved (`payload.integrationId`); it is applied; Git reports a merge conflict (summary `<n> conflicting paths`, up to 20 `paths`) or a proven pre-apply refusal (summary = the reason) |
| `paused`, `resumed`, `retried`, `cancelled`, `completed`, `failed` | Run control and settlement: a pause (by a person or for a due gate), a resume, a retried attempt (`runs.retryTask`) or cancellation (`runs.retryCancellation`), and the run's final status |
| `cleanupPrepared`, `cleanupApplied`, `cleanupAbandoned` | A cleanup preview is published; every selected resource is retired; a cleanup in attention is abandoned (summary `<n> resources`, payload `cleanupId`, `resourceCount`) |

`runs.timeline {runId, cursor?, limit? (1..200, default 50), kinds?, taskId?}` merges those events with the run's messages (`status`, `handoff`, `merge_ready`, `decision_gate`, `escalation`, `question`) exchanged between the run's coordinator, dispatch and attempt terminals, newest first, bodies capped at 4 KiB with `truncated`. Inbox traffic from `ext:` addresses never appears in a run timeline. The timeline replaces the former Agent Conversations view.

Every timeline entry also carries `workspaceId`, `sha` and `baseSha`, null unless the event recorded them: `taskCompleted` of an isolated attempt (attempt workspace, completion commit, launch base), `integrated` (integration workspace, integrated commit, expected base) and the isolated run's `completed` (integration workspace, integration commit, source commit). A shared task's `taskCompleted` names only its workspace. Desktop offers Open Diff on an entry with a commit range whose workspace is still local and active. Events recorded before a field existed carry nulls.

## Resources And Cleanup

An isolated run retains its attempt worktrees, their branches and the integration workspace after it finishes, fails or is cancelled. Nothing is deleted automatically. `runs.resources` lists them, `runs.previewCleanup` reviews a selection of at most 25 resources (branch removal is opt-in per resource), and `runs.applyCleanup` requires the preview's `digest` and `confirm: true`. `runs.retryCleanup` and `runs.abandonCleanup` handle cleanup that needs attention. Reservation and recovery rules are in [runs integration](runs-integration.md#cleanup).

## Buckets

`runs.board` groups runs into three buckets, computed by the `orchestrationBoardRuns` view:

- **Attention**: a cleanup in attention; a cancelled or failed run with integration or cancellation attention; or an unfinished run with an `attentionReason`, coordinator attention, a failed, stalled or blocked task, a due gate, or a launch, workspace or integration in attention or an unevidenced conflict.
- **History**: `completed`, `failed` with nothing left to settle, and `cancelled` once settled.
- **Active**: everything else.

Counts ignore the selected bucket and page so they describe the whole filtered result. Items sort by creation time and id, newest first. Filters are bounded, and paging requires the board `revision`: after a change the client reloads the first page instead of appending inconsistent pages. Runs whose workspace or project no longer exists stay visible.

SQLite triggers advance the board revision in the same transaction as any run, task, dispatch, gate, event, workspace or project change. Runs reads (`board`, `snapshot`, `task`, `timeline`, `source`, `plan`, `gates`, `gate`) execute outside the host actor with at most four active and sixteen outstanding reads and a 25 second deadline; excess reads fail with a retryable busy error.

## Runtime API

Every `runs.*` and `recipes.*` request uses camelCase keys and rejects unknown fields. Mutations take a client `requestId`; a replay returns the stored receipt from `runCommandReceipts` instead of acting twice.

| Verb | Purpose |
| --- | --- |
| `runs.board` | Paged run summaries with `counts {attention, active, history}` and `revision`. Each summary has `pendingGates`: up to five due gates, newest first, as `{id, kind, taskId?}` (`taskId` absent for run gates), so a client can open the gate directly |
| `runs.snapshot` | One run: plan state, coordinator, integration, pending gates, cleanup, `controlSequence`, `resourceCount` (retained workspaces not retired by a cleanup, 0 for shared runs), and a page of tasks with their attempt, integration and `startedAt`, `completedAt`, `updatedAt` (SQLite UTC timestamps without a zone) |
| `runs.task` | Task inspection: result, attempt, gates, history |
| `runs.timeline` | Events and messages, newest first |
| `runs.source` | The source snapshot (commit, path, project) New Run shows |
| `runs.create` | Create a run and launch its coordinator |
| `runs.plan` | The current plan or one revision |
| `runs.gates`, `runs.gate` | Gates of a run; one gate with the plan (plan gates) or evidence tasks (stage, decision, stall) |
| `runs.resolveGate` | Resolve a gate with an option id, a reason, optional `taskIds`, and `expectedEvidenceDigest` |
| `runs.control` | `cancel`, `pause`, `resume`, `replan`, guarded by `expectedSequence` (`run_sequence_stale`) |
| `runs.retryTask`, `runs.retryIntegration`, `runs.retryCancellation` | Retry an isolated attempt or integration in attention (run paused first), or a cancellation in attention |
| `runs.resources`, `runs.cleanups`, `runs.previewCleanup`, `runs.cleanup`, `runs.applyCleanup`, `runs.retryCleanup`, `runs.abandonCleanup` | Retained resources and reviewed cleanup |
| `runs.integrations`, `runs.integration` | Integration receipts of an isolated run |
| `recipes.catalog`, `recipes.recipe`, `recipes.validate`, `recipes.savePersonal`, `recipes.previewExport`, `recipes.applyExport` | [Recipe catalog](recipes.md) |

The coordinator side stays in `orchestration.*`: `orchestration.planContext` and `orchestration.planPropose`. `orchestration.gateCreate` creates a decision gate and `orchestration.gateList` lists decision gates of tasks outside runs.

Capabilities `runsV1` and `recipesV1` are advertised in the control file, `status.get` and `MOBILE_HELLO_CAPABILITIES`. A client without them shows Update Required; the CLI answers "A live Alera runtime host does not support runsV1. Restart Alera and retry." The host broadcasts `runsChanged {revision}` and `recipesChanged {source, catalogRevision}` to every authenticated client, phones included; both names are in the Dart `runtimeHostEventNames`. The run timeline also refreshes on `conversationsChanged`.

Terminals a run starts carry host-owned tab payload keys: `runId` on the coordinator and every worker, and `runTaskId` on workers. A client `tab.upsert` cannot drop or rewrite them, and a client-created tab cannot claim them. A terminal handed a task with `delegate --terminal` is not tagged.

## Actors And Authorization

There is no separate approval credential. The authenticated session authorizes a decision, `expectedEvidenceDigest` and `expectedSequence` keep it current, and the actor is derived from the connection, never from the payload: `desktop` (the local app), `cli`, `mcp:<client>` (a local CLI invoked with an MCP `externalOrigin`), `mobile:<deviceId>`, `agent:<handle>` for plan proposals, and `runtime`. The actor is written on the gate, on the `orchestrationAuditEvents` row and on the timeline event in one transaction.

Paired phones and relay clients may call all 23 `runs.*` verbs plus `recipes.catalog` and `recipes.recipe`. Recipe writes, every `orchestration.*` verb, `host.process.run` and `inbox.wait` stay local-client-only. `runs.applyCleanup` requires the preview digest and `confirm: true`, `runs.control` requires `expectedSequence`, and a rejection cancels the run with the device recorded as actor. A satellite forwards run and recipe reads to its hub; the hub reverse policy denies every run and recipe mutation, including `runs.previewCleanup`.

## Surfaces

- Desktop: **Activity** (application menu, the status-bar attention chip, or `Mod+Shift+A`) is a shell overlay with a Runs, Questions and Automations rail. Runs groups Attention, Active and History; a run opens on Overview (gate cards first, objective, facts, actions), Tasks, Timeline and, for isolated runs, Resources. New Run picks the workspace, isolation, template, profiles, concurrency and Require Plan Approval. Selecting a run never changes the active workspace. Settings > Recipes manages the catalog. A "Run Needs Attention" notification fires when the attention count grows while Activity is not visible in a focused window.
- Mobile: the Activity screen offers the same three sections, run detail with Overview, Tasks and Timeline, gate cards, cleanup, and New Run. A gate push opens the run at that gate.
- CLI: `alera orchestration run|plan|gate|recipe ...`; see [orchestration](orchestration.md#cli).
- MCP: `list_runs`, `show_run`, `get_run_timeline`, `create_run`, `resolve_run_gate` and the other run and recipe tools, documented by the `alera-mcp-orchestration` skill.

## Upgrading To Schema v3

Orchestration schema v3 (`orchestration.schemaVersion = "3"`) starts from scratch. When the runtime opens a store at version 1 or 2, or with any pre-v3 orchestration or workflow table, it first writes a full copy to `<runtimeDir>/runtime-pre-runs-v3.sqlite` (mode 0600, never overwritten), then in one transaction drops every orchestration and workflow table, view and trigger, renames `personalWorkflowRecipes` to `personalRecipes`, installs v3, and restores inbox questions from `ext:` addresses with their replies (a `decision_gate` question becomes `question`). Agent Profiles, their launch receipts, Personal recipes and SSH targets are kept. Runs, tasks, gates and agent messages are discarded and the count is logged as a warning; the retired `desktop-workflow-approval.key` is deleted. Worktrees and branches created by earlier workflows stay on disk and in Git. An unknown future version fails closed and leaves the store untouched.

Only the runtime host runs the reset, after it holds the runtime owner lock. Any other process that opens a pre-v3 store (an `alera` CLI command, an agent's `alera` after the binary was replaced) fails closed and asks to restart Alera, because a host that still runs may be using the tables the reset drops. A backup left by an attempt that did not commit is kept, and the fresh copy goes beside it as `runtime-pre-runs-v3-1.sqlite` (then `-2`, and so on).
