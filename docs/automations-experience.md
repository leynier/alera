# Automations Experience

This is the reference for how automations behave today on the desktop, the phone, the CLI and MCP. The definitions, runs and audit history live in the runtime host; every client reads and edits the same catalog through it. The pure Dart domain both apps share (records, runs, readiness, the draft, reuse policy, composer properties and seeding, labels, catalog grouping and target summaries) lives in `packages/alera_automations`; controllers, repositories and presentation stay in each app.

## Composer

New and existing automations open in one prompt-first composer (`lib/src/features/automations/presentation/composer/`, and `mobile/lib/src/features/automations/presentation/composer/` as a full-screen form with sheets). It replaced the four-step wizard. The surface is a name, the prompt, one property chip each for Schedule, Destination, Agent, Reuse and Options, the live Next Runs and Readiness lines, then a collapsible Description and the Options groups.

- **Prompt.** Typing `{{` lists the variables the runtime fills and Tab or Enter inserts one; known variables render as tokens and unknown ones as errors. Control+Enter or Cmd+Enter submits.
- **Schedule.** Presets for Weekdays At, Daily At, Weekly On Days At, Every N Hours, Once At and Custom Cron, in an IANA timezone.
- **Destination.** A sectioned picker of Running Agents, New Tab In A Workspace, New Worktree (from a local Git project or as the child of a workspace) and Project Folder. The chosen destination then asks only for what it still needs: a source branch, a project folder, or the conversation.
- **Agent.** The agent profile. Hidden for an existing conversation, which keeps its own agent. A new automation starts with the profile used last in the session, else the settings default, else the only profile.
- **Reuse.** Shown only when the runtime advertises `automationReuseV1`. It offers the policies that apply to the destination (see Reuse Policy And Bound Target); an existing conversation shows the fixed label Continues Conversation.
- **Options.** The chip counts the options that differ from their defaults.

Context seeding. A composer opened from a workspace targets a new agent tab in that workspace and files new workspaces in its section; from a local Git project it targets a new worktree of that project and fills the source branch New Workspace would preselect once the branches load; from a non-Git project it picks the project's folder when there is exactly one; from a section it only sets the section (and the project, when every workspace in the section belongs to one); anywhere else it sets no destination, so the user chooses one. Seeded destination fields are marked From Context. Changing the destination keeps the chosen agent profile and section. The composer opens from the Automations section of Activity, the workspace context menu, a section header, and the Command Palette action New Automation (seeded from the active workspace).

Live feedback. Every edit is checked locally at once. Once the draft is complete the runtime checks it with `automation.readiness` 600 ms after the last edit, and a readiness issue outlines the chip it is about in red. Next Runs comes from `automation.previewSchedule`. Closing with unsaved changes asks before discarding. The primary action is Create And Activate for a new automation, Save And Activate for a draft and Save Changes otherwise; Save As Draft is available while creating.

Options only appear when they apply, and are left out rather than disabled:

| Group | Contents | Shown When |
| --- | --- | --- |
| Schedule Limits | Starts, Ends, Max Scheduled Runs, Missed Schedules (misfire policy) | The schedule is recurring |
| Reliability | When Runs Overlap, Inactivity Timeout (default 2 hours), Retry Attempts (1 to 3, default 3), Precheck Command and its timeout (default 120 s) | Always |
| Workspace | Workspace Name Template, Section, Workspace Tags; Workspace Setup for a new worktree; Cleanup only when every run gets its own workspace | The destination creates a workspace (worktree or project folder) |
| Notifications | Notify On Success | Always |

The other numeric fields of a definition have no control: queue cap 10, heartbeat interval 60 s, misfire grace 900 s, retry backoff 60 s, circuit failure threshold 3, and circuit open 900 s. Editors keep the stored values of these fields and send them back unchanged, and the runtime still validates and honors any value sent through `alera automation create|edit --file` or the MCP definition JSON. The bounds live in `AutomationNumericField` and mirror `validate_definition` in `rust/alera-core/src/runtime/automation_store.rs`.

## Destinations

A definition has exactly one target, and its type is always chosen explicitly; context can only fill the fields of the chosen type.

| Target (`target` key, CLI `--target`) | Composer Choice | Behavior |
| --- | --- | --- |
| `freshTab` (`fresh-tab`) | New Tab In A Workspace | Opens a new agent tab with the profile in an existing workspace |
| `worktree` (`worktree`) | New Worktree | Creates a Git worktree and branch on this computer for each run, from `projectId`, `parentWorkspaceId` (the project comes from that workspace and the worktree is nested under it), or both. A retried attempt reuses the worktree its run created |
| `projectCheckout` (`project-checkout`) | Project Folder | Opens a workspace in the registered local or SSH project folder on `hostId` |
| `existingTab` (`existing-tab`) | Continue An Agent Conversation | Sends the prompt to a live agent conversation captured with its `conversationId` |

`managedWorkspace` (with `sourceWorkspaceId`) and `projectWorktree` are the older spellings of `worktree`; the runtime and the Dart parser still accept them and write `worktree` back. The CLI keeps `managed-workspace` and `project-worktree` as aliases. An older app attached to a newer host sees `worktree` as an unknown target kind and shows it as unsupported.

## Reuse Policy And Bound Target

`reusePolicy` decides where runs after the first one go. It is additive under `automationReuseV1` (control file, `status.get`, `MOBILE_HELLO_CAPABILITIES`), and clients send it only to a runtime that advertises the capability.

| Policy | Later Runs | Available For |
| --- | --- | --- |
| `newEachRun` (default, omitted on the wire) | Every run creates its destination | New tab, worktree, project folder |
| `reuseWorkspace` | Open a new agent tab in the workspace the first run created or used | Worktree, project folder |
| `reuseConversation` | Continue the first run's agent conversation while it is available | Every destination; the only one for an existing conversation |

The runtime rejects `reuseWorkspace` on an `existingTab` target and any reuse combined with `cleanupPolicy: onSuccess`, because cleanup would remove what the automation returns to.

`boundTarget` (workspace, optional tab, conversation and agent profile, the run that bound it and the last run that reached it) is runtime-owned. The dispatcher writes it after a run reaches its destination, `automation_binding_store.rs` edits it in place without bumping the revision, and `upsert_automation` never takes it from a client: it keeps the stored binding, and drops it when the target changes or reuse is turned off. Catalog items carry `boundTarget` and a readable `boundTargetSummary`, marked `(missing)` when the bound workspace or tab is gone. An existing-conversation target starts bound to the tab it names.

Before each attempt the resolver (`server/automation_bound_target_resolution.rs`) reads the binding fresh from the store, never from the run's frozen definition:

- No binding: create the destination the target names and bind to it.
- Bound workspace removed, archived, or no longer matching the target: clear the binding and create a new destination.
- Bound workspace on an SSH host whose link is not attached: wait (`waitingForRemoteHost`).
- `reuseWorkspace`: open a new agent tab in the bound workspace.
- `reuseConversation` with a live, injection-ready agent: paste the prompt into it.
- Agent busy, or the session serving another run: park the run (`waitingForBoundConversation`).
- Terminal or agent gone: relaunch the conversation (resuming the native session when one was captured) in a copy of its tab in the same workspace. Only an automation-owned tab is closed first; a person's own tab is never relaunched or removed in place.
- Bound tab taken over, its conversation changed, or a person's tab whose agent exited: release the tab and open a new tab in the bound workspace, which becomes the new binding.

A parked run stays Pending and spends no attempt; it is retried every few seconds. Past the misfire grace window (at least 60 seconds) the overlap policy decides: `forceParallel` opens a parallel tab in the bound workspace without moving the binding, and anything else ends the run as `overlapSkipped` ("bound conversation stayed busy past the misfire grace window").

Takeover releases the bound tab when the run's tab is the bound one, and so do an inactivity timeout or a cancellation that ends a run in an automation-owned tab, so the next run opens a new tab in the same workspace. Removing the tab releases it the same way; retiring the workspace clears the binding. Recovery that replaces a tab moves the binding to the copy. `automation.unbind {id, reason?}` (CLI `alera automation unbind`, MCP `unbind_automation_target`, desktop and phone Unbind, allowed for mobile) forgets the binding so the next run creates and binds a new destination. Every binding change is audited (`targetBound`, `boundTabReleased`, `targetUnbound` with its reason).

A run delivered to a reused conversation or workspace starts with a short preface naming the run number, the automation, and the previous finished run's summary and error (each bounded to 512 bytes). The preface is dropped rather than pushing the prompt past its 128 KiB limit. Runs record how they reached the target in `reuse` (`bound`, `conversation`, `resumedConversation`, `workspace`).

## Catalog

The Automations section of Activity (`Mod+Shift+A`, then Automations in its rail) lists the definitions of the connected runtime. One filter bar holds the status buckets, Project, Agent Profile, Host (when there is more than one), the scope the page was opened with, and a search over name, slug, description and prompt; Clear Filters is always reachable.

- **Buckets.** Needs Attention (blocked, or carrying attention, and not trashed), Active, Paused, Drafts, Completed, Trash. Without a bucket every definition except trashed ones is listed.
- **Scopes.** All, a project, a section or a workspace, following the runtime-derived association: the origin workspace decides where a definition is listed, independently of where it runs, and its section follows workspace moves. The workspace scope lists what is scheduled there (Scheduled Here) and, separately, the runs that used that workspace.
- **Grouping.** Groups follow the sidebar's Group By (project or section) with one collapsible header and count per group, ordered by label, with the unplaced ones last. Within a group, definitions needing attention come first, then by state (active, blocked, paused, draft, completed, trashed), then by name.
- **Rows.** Name, state, last run and, for a reusing automation, where it is bound. Hover or focus reveals the quick actions (Activate, Pause, Resume, Restore, Run Now or Run Again, Edit) in reserved space; the more menu holds Clone, Pause And Cancel Runs and Move To Trash.

The phone uses the same buckets as chips, the other filters in a sheet, the same project groups and the bound line on each card.

## Detail

The detail shows the header (name, state, description and lifecycle actions: Activate, Pause, Pause · Runs Keep Going while runs are active, Resume, Restore, Edit or Fix Problem, Run Now or Run Again with Run Without Precheck, Queue After Active Run and Run In Parallel), the facts (Schedule, Destination, Last Run, Shown In, Created By), the collapsible prompt with Copy Prompt, the binding card, and Runs and Activity tabs.

The binding card appears only for a reusing automation on a runtime with `automationReuseV1`. It says Not bound yet, Bound to the summary with Open and Unbind, or warns that the bound workspace or tab is missing and what the next run will do. Unbind, Move To Trash and Pause And Cancel Runs ask for confirmation. Activation of a draft uses `automation.resume`, which runs the same readiness check.

Runs can be filtered by All, Running, Failed and Skipped; the selected run opens its panel above the list, and consecutive missed runs from older runtimes collapse into one row. Activity is the audit trail, newest first.

## Lifecycle

Saving activates the automation; Save As Draft keeps it inactive. Active edits stay Active and apply to future runs, while admitted runs keep the definition revision they froze. Pause stops scheduling while admitted runs can continue; Pause And Cancel Runs also cancels them. Resume restarts scheduling from now. Trash is recoverable and Restore returns a definition Paused, or Completed when it was completed. A one-time automation completes when its run ends, and a recurring one when it reaches its maximum scheduled runs. Completed definitions can be cloned, run again and trashed. Clone creates a new automation with the same settings and target (desktop and phone Clone, CLI `clone`, MCP `clone_automation`).

Run Now runs once without changing the schedule, with the definition's precheck and overlap policy unless overridden, and works for technically valid Draft, Paused, Active, Blocked and Completed definitions. Run Again creates a new linked run, either in the previous run's preserved workspace with its context or fresh; on a reusing automation the binding decides where it goes.

## Removed Features

- **Approval and policy gates.** There is no revision approval, repository declaration, project approval or per-profile automation permission. Technical validation of the prompt, schedule, target and launchable profile is the only gate. `automation.approve` stays on the host as a deprecated activation alias for older apps, and the hidden CLI `approve` subcommand still parses; current apps activate through `automation.resume`. `automation.policy` is gone.
- **Templates, tags, import and export.** The portable catalog was removed from the host, CLI, MCP, desktop and phone. `tagIds` remains an ignored definition field, and `retire_removed_features` drops the old tables at startup.
- The retired `automation.policy`, `automation.templates`, `automation.tags`, `automation.import` and `automation.export` verbs fall through to the generic unknown-request error.

Migration reactivated only technically valid definitions with unambiguous audit evidence that a removed gate had stopped a previously active automation (`retiredGatesMigrated`). Technical failures remain Blocked; ambiguous history, ordinary drafts and manually paused definitions are preserved.

## Runtime Boundaries

Creation does not enable login autostart or change keep-runtime settings. A runtime must be running to execute schedules.

Scheduled admission and the occurrence claim commit together, and each run freezes its admitted definition revision. Overlap is decided by one pure function (`alera_core::runtime::automation_overlap`) that `start_automation_run` alone calls, for scheduled, manual and resumed runs. Only a blocked scheduled run blocks its definition. Pending runs remain eligible when their definition is paused. The inactivity timeout counts from the latest of the run start, a heartbeat and agent hook activity.

Misfires. An occurrence is a misfire when it was due before the runtime started or is older than the misfire grace window. The default `skip` policy drops misfires; `runLatestOnce` runs only the latest one; `queue` runs them all. Skipped occurrences create no run rows: they are claimed in one batch per tick and recorded as a single `misfiresSkipped` audit entry with the count and the first and last scheduled times. Recovering an already admitted run is a separate path.

Recovery. Reconcile the owner before launching. Resume a captured native conversation once, then continue with context in the preserved workspace. Recovery persists three total launches by default, 60/120 second backoff and the original 24-hour deadline, and a restart does not reset that budget. The retry prompt carries the original task, the previous summary and error, and bounded local Git status and diff statistics; it never copies terminal output or file contents. The saved agent launch configuration and permissions remain authoritative. SSH recovery directs the agent to reconcile the preserved remote files.

Observation. Watch Terminal attaches read-only to a live session or a retained checkpoint (`createOrAttach` with `attachmentMode: observe`, or `terminal.observe`; the phone forwards observation through `terminal.attach`). It cannot write, resize, reclaim, terminate or restart that session. Generic terminal restoration excludes automation-owned tabs until Take Over, and the automation runner alone decides whether to resume or retry them. Take Over explicitly stops automatic recovery, preserves the workspace and releases the bound tab. Legacy generic attachment keeps its takeover semantics.

Owners. Targets stay reserved until process closure is proven. Process identity includes a PID and start marker, and Linux also persists the boot identity. A timed-out run can retain its reservation, and new work waits for the previous owner. A live or unverified owner is never replaced merely because its transport disappeared, and a healthy SSH owner is reattached without injecting another startup command.

History. Attempt terminals and output are preserved by default. Run Again keeps the original run's final history. A successful later run clears historical failure attention.

## Events

| Event | Payload | Sent When |
| --- | --- | --- |
| `automationsChanged` | `{automationId}`; empty for a bulk change such as purge | Any definition change, including binding changes, state changes, misfire batches and one-time completion |
| `automationRunChanged` | `{automationId, runId, status}` | Every run status transition, including parking |
| `automationAttentionRequired` | `{automationId, runId, reason}` | A run needs a person |

The payloads are additive and never bump `aleraTerminalHostProtocolVersion`. All three names are in `runtimeHostEventNames`, so the desktop catalog and detail refresh on host events.

## Agents, CLI And MCP

The `alera-automations` CLI skill (`skills/alera-automations/`) and the `alera-mcp-automations` MCP skill (`edge/skills/alera-mcp-automations/`) describe authoring and the run lifecycle contract. CLI creation accepts flags or partial JSON with server defaults and an idempotent `--request-key`; `--target` is always explicit, `--reuse none|workspace|conversation` sets the policy, `show` prints the binding and `unbind` forgets it. The CLI refuses `--reuse` and `unbind` against a runtime without `automationReuseV1`. MCP exposes the same verbs, including `unbind_automation_target`.

## Validation

- `packages/alera_automations` (`dart test`): domain parsing including the legacy worktree keys, draft editing and round trips with hidden limits, reuse policy applicability, composer properties and seeding, catalog query and grouping, target summaries, schedule presets, status labels, prompt variables and run presentation.
- Desktop: `test/unit/features/automations/` (composer defaults and request keys, draft and worktree drafts, catalog provider, runtime events) and `test/widget/` (`automation_composer_test.dart`, `automation_detail_test.dart`, `automations_page_test.dart`, `automation_prompt_editor_test.dart`, `automation_run_panel_test.dart`), plus the design-system component tests for the popover, property chip, sectioned picker, collapsible section and duration, time and date-time fields.
- Mobile: `automation_composer_test.dart`, `automation_screens_test.dart`, `automation_repository_test.dart`, `automation_composer_request_key_test.dart` and `alera_composer_fields_test.dart`.
- Core (`rust/alera-core`): binding store, definition serde (including the legacy target spellings and reuse fields), overlap decisions, run and recovery stores, and agent profile removal impact.
- Runtime and CLI (`rust/alera-cli/src/terminal_host/server/automation_*_tests.rs`): definition requests, events and misfire batching, reuse resolution, dispatch and lifecycle, project worktrees and checkouts, prechecks including SSH, circuit breaker, run lifecycle, dispatch errors, shared cleanup and authoring retries, plus the CLI parser tests for the retired subcommands.
- Headless runtime integration (`rust/alera-cli/tests/terminal_host_headless_runtime/`): `automation_recovery_case.rs` restarts the runtime process and recovers into a new attempt in the same workspace while keeping the deadline, observing read-only and never replaying a completed automation terminal; `automation_reuse_case.rs` returns a reusing automation to its workspace, keeps the binding across a runtime restart and rebinds after `unbind`.
- Landing keyboard shortcut and demo fidelity, skill version digests and the MCP skill catalog.

Runtime integration runs on Linux with simulated agents. Physical reboots and live macOS, Windows or SSH-machine failure scenarios are not covered by automated tests.
