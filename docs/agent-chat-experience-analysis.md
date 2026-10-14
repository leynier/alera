# Agent Chat Experience Analysis

Status: historical proposal at the baselines below. Implementation and current verification are tracked in [the implementation plan](agent-chat-experience-implementation.md). This is a reviewable analysis and specification for bringing Alera Agent Chat as close as practical to the T3 Code chat experience while keeping Alera's Flutter design system, host-owned runtime, and accepted product decisions. Nothing described under "Target" exists yet unless it is marked as current behavior.

Baselines: Alera `2efa844892f9831a00096bd8215ae702ad85333b`; T3 Code reference `reference_projects/t3code` at `df26ef99859ac757409f5332b185a89cc7f40267`.

Verification: source-only. No build, code generation, test, app run, Mac UI session, or live provider was used. "Observed" means read in source at the baselines above. "Inferred" means reasoned from source structure or file and widget names without tracing. T3 Code behavior is cited from its source, mostly through six earlier source reviews; the points that decide Alera's design were re-checked against the code.

## Executive Findings

1. The requested experience (New Agent Chat opens directly, provider and model chosen in the composer) is blocked by the runtime lifecycle, not by widgets. `agentChat.create` persists the chat and tab and then immediately runs `ChatOp::Recover`, which starts the provider process (`rust/alera-cli/src/terminal_host/server/agent_chat_runtime/runtime_handle.rs:345`, `session_config.rs:219`). A provider switch also starts a process even on an empty chat (`session_config.rs:58`). One source review claimed create starts nothing; that claim is wrong.
2. The existing deferred-turn path already starts a stopped chat on its first `send` (`session_turns.rs:213-214`, `:289-293`), so a host-owned draft with deferred native start reuses an existing path, but it also changes recovery, close, title, credential injection, delegation, and cancellation timing; its size is not estimated here and each of those needs regression coverage. Client-only drafts like T3's would break host-owned tabs and phone sync and are rejected.
3. Alera keeps cross-provider switching with a transcript handoff after the first message, which T3 does not offer (T3 locks the provider, `ChatView.logic.ts:1018-1043`). Before the first send, provider and model choices become free and silent; after it, one confirmation remains; while busy, the existing idle guard (`session_config.rs:15-27`) stays.
4. Providers and models have no Settings surface and no write path. Instances come only from a hand-edited `<runtimeDir>/agent-chat-providers.json` (`instances.rs:12`), re-read on every catalog call (`catalog.rs:27`). Production model discovery does not exist (`provider_factory.rs:85-91` returns `None` and production does not override it). `available` only proves an executable or connection config resolves (`production_factory.rs:87-139`); it says nothing about sign-in.
5. The "Provider default" catalog entry has `id: null` (`catalog.rs:140`), but Dart rewrites it to `''` (`packages/alera_agent_chat/lib/src/agent_chat_provider_catalog.dart:15`). The host happens to treat `configure {model: ""}` and `{model: null}` as "reset to default" (`commands.rs:146-153`, `agent_chat_deferred.rs:181-185`), yet Dart cannot express an explicit null because `toJson` omits null keys (`agent_chat_inputs.dart:180`). Reset must become an explicit, documented wire meaning.
6. The transcript skeleton is sound, but failed and stopped turns fold away (`agent_chat_timeline_projection.dart:160`), approvals sit at the timeline tail with no footer signal, and scroll and fold state are lost on tab switch. These are client-side fixes in the shared package and widgets.
7. Chat orchestration is richer than T3's (cross-project and cross-host targets, human delegation, recursive cancel, durable wakes), but parents barely show their children in place. Activity stays the only cross-chat hub; the chat gains a Tasks dock, a child-input banner, a parent link, and attention signals that never navigate.
8. Reasoning effort is not in the runtime contract (`docs/agent-chat.md:45`); Dart parses fields the host never sends. Fork, rewind, delete, approval history, per-turn diffs, and provider-native subagent lineage all need backend extensions and are separated from quick presentation work.

## Accepted Requirements

- New Agent Chat opens a chat tab directly with the composer focused. No provider-selection modal on desktop or phone.
- Provider and model are chosen in the composer. Settings gains a Providers section that covers models, including host model discovery and verified sign-in status; both are part of the required total scope (Phase 7), not optional extras.
- Chats coexist with terminals. The local or remote runtime owns the persisted chat, the provider process, and synchronization.
- Desktop and paired mobile reach parity for chat control.
- A provider switch keeps the same chat and hands context to the new provider.
- No import of legacy Codex tabs.
- Cross-project messaging and delegation target an existing chat, a new chat in an existing workspace, or a new isolated worktree or shared workspace.
- Chat orchestration stays separate from terminal orchestration.
- Background events never navigate automatically. This is a navigation rule only; it does not forbid steering a wake into an active turn (see Wakes below).

## Reproduce Versus Intentionally Differ

| Experience | T3 Code | Alera target | Why |
| --- | --- | --- | --- |
| New chat | Client draft route, server thread created on first send | Host-owned draft: chat and tab persisted at once, provider started on first send | Tabs are host records synced to the phone |
| Empty draft reuse | Reuses an empty draft for the project | Focus an existing never-sent chat in the same workspace when its local draft is empty | Same intent, host-owned identity |
| Provider after first send | Locked to the same provider | Switchable with one confirmation and a transcript handoff | Accepted Alera capability |
| Picker | One searchable provider and model popover, favorites | Same structure on `AleraPopover` and `AleraSectionedPicker`; favorites later | Reproduce, with design-system components |
| Defaults | Project, then current composer, then remembered, client and server mix | Proposed: project, launching chat, explicit default, remembered, first enabled and available; host-persisted and synced | Multi-device parity; the explicit default level is an Alera addition T3 does not have |
| Queue and steer | Enter queues, Mod+Enter steers, queued items editable and promotable | Enter auto, Mod+Enter steer when supported, queue Edit and Remove; promote-to-steer needs a host verb | Atomicity on the host |
| Requests | Drawer above the composer with typing guard | Request dock in the footer slot used by questions, typing guard | Reproduce |
| Wakes | Can steer into an active parent turn | Delivered only when the parent is idle with no pending request | Current Alera behavior that this proposal retains; not a user requirement (Open Decision 7) |
| Lineage | Side panel, one environment | Tasks dock in the chat plus Activity, across projects and hosts | No thread-details panel; wider reach |
| Worktree and branch | Picked in the composer | Owned by the workspace; delegation picks a target workspace | Workspace model |
| Settings scope | Environment selector | Host selector (This Device and Remote Hosts) | Same idea, Alera vocabulary |
| Notifications | Toast with Open Thread or OS notification | Same, never navigates on arrival | Reproduce under Alera rules |

## Comparison Matrix

| Area | T3 Code (observed) | Alera today (observed) | Target |
| --- | --- | --- | --- |
| Lifecycle | Draft on client, `startThreadTurn` carries `bootstrap.createThread` (`ChatView.tsx:9958-10036`) | Modal, then eager create and provider start (`new_agent_chat_dialog.dart:109-147`, `runtime_handle.rs:345`) | Direct open, host draft, deferred native start |
| Composer | Combined picker (`ModelPickerContent.tsx`), traits picker, compact menu below 620px | Separate provider and model menus, always-confirm switch (`agent_chat_composer_controls.dart:71-106`, `:180-189`), chips hidden while catalog loads (`agent_chat_footer.dart:152`) | Combined picker, conditional confirm, visible disabled chip while loading, compact overflow |
| Transcript | Live work row, failed turns unfolded (`MessagesTimeline.logic.ts:1108-1117`), three scroll modes | Every action expanded while running, failed turns fold, follow-on-change scroll, state lost on tab switch | Turn grammar in the shared package, scroll model, per-chat session state |
| Questions | Drawer with paging | Docked with paging, per-request drafts, keys 1-9 (good) | Keep; merge into one request dock |
| Approvals | Drawer, Approve and Decline plus More (`ComposerPendingApprovalActions.tsx`) | Timeline cards at the tail, no footer signal, desktop never confirms Full Access | Dock with paging, runtime decision order, Full Access confirmation on both surfaces |
| Plans | Proposed plan rows | Plan progress in the desktop footer, inline on mobile | Docked plan progress on both; Implement In New Workspace action on plan cards |
| Usage | Context meter, usage-limit banner with reset time | Desktop context ring only; mobile usage sheet | Desktop usage popover with reset times; no resume-at-reset |
| Model settings | Settings Providers with status, auth, models, secrets | None; file-only instances, no discovery, `available` only | Settings Providers on a host store with keyring secrets |
| Recovery | Error banners clamped, setup links | Resume or Start New Session from verified recovery (`session_provider.rs:177-225`), reconnect reload | Keep; add Open Provider Settings for unavailable providers; ready-state hint for drafts |
| Mobile | Same draft model, settings sheet | Sheet with Agent and Model only (`new_agent_chat_sheet.dart`), tune sheet, queue Edit, reversed list | Same rules as desktop from shared package logic; keep sheet and reversed list |
| Orchestration | Agent-only delegation, lineage panel, child-input banner | Human and agent delegation across projects and hosts, Activity Chat Tasks, minimal in-chat dock | In-chat Tasks dock, banner, parent link, wake cards; Activity remains the hub |

## Journeys

### J1. Start a chat

Target: `Mod+Shift+T`, the pane add-tab menu, and the phone "+" call `agentChat.create` at once with the resolved default selection, open the tab in the target pane group, and focus the composer. Current rules stay: `activateOnlyIfCurrent: true`, focus guarded by `workbenchFocusIsParked()`, no workspace switch. The phone selects and focuses the new tab because the person asked for it.

- Default resolution (proposed precedence, all host-persisted, Open Decision 2): project default selection, then the selection of the chat the command was launched from when it is in the same workspace, then the explicit default for new chats when set, then the remembered selection from the last successful first send, then the first enabled and available instance with its default model. A level whose instance is disabled or unavailable is skipped. T3 has project, current composer, and remembered levels only; the explicit default is an Alera addition.
- Empty state: provider icon and label by instance id (not by provider kind), model label (not raw id), workspace path, and "Send a message to start." A never-sent chat must not show "The agent session stopped." (`agent_chat_status_views.dart:139-141`).
- Reuse: when the workspace already has a never-sent chat whose draft on this client is empty, New Agent Chat focuses it instead of creating another. Reuse only focuses; it never deletes or rewrites anything, so it is safe even when another client is typing in that chat. Composer drafts are client session state today, so the host cannot see another client's unsent text: a chat with no items on the host never proves there is no unsent work. Two clients pressing New Agent Chat at once may create two chats; that is accepted, and each client action carries a `requestId` so its own retries never duplicate.
- Host restart: a never-sent chat comes back `stopped` with no recovery, and clients derive never-sent from the snapshot, so they show the ready empty state, never "The agent session stopped." The composer draft survives a host restart or reconnect because it lives in the client; it is lost when that client app restarts unless a later change persists drafts. A chat whose first send reached the host before the restart has a user item and shows the normal recovery.
- No available provider, current host contract: `agentChat.create` requires a `providerInstanceId` or `provider` that `instances.provider_of` resolves and that has `provider_traits`, otherwise it answers `providerUnavailable` (`runtime_handle.rs:187-204`). It does not check availability, and built-in provider ids always resolve (`instances.rs:94-104`). The existing API cannot create a durable chat without a selection.
- Known but unavailable (the resolved default is not installed, misconfigured, or signed out): create the chat with that selection. With deferred start nothing spawns; the chip shows the provider with its reason, Send is disabled, and the chip offers Open Provider Settings. Without deferred start the host starts eagerly as today and the chat shows the existing recovery.
- Zero enabled or configured instances (possible once Phase 5 lets a person disable instances): never pick an arbitrary instance to satisfy `create`. Recommended contract extension `agentChatUnselectedDraftV1`: `create` without a selection persists a chat with `providerInstanceId: null`, spawns nothing, refuses `send` with `providerRequired`, and accepts a later `configure` that sets the first selection without confirmation. The chip reads "No Agent Available" with Open Provider Settings. On a host without that capability the pane shows the same empty surface unpersisted (no tab record, nothing on the phone) and creates the chat once a selection exists.
- Catalog request fails: show a toast with Try Again and Open Settings and create no tab.
- Older runtime without the deferred-start capability: open directly anyway; the host starts the process eagerly as today. This is a temporary cost, not a reason to keep the modal.
- Title: while the title is the default provider label, the host replaces it with the first line of the first message, trimmed and capped. A rename by a person stops automatic titling. Provider switches before the first send relabel an untouched default.
- Archived chats lose their only home when the dialog goes. Desktop adds Archived Chats to the add-tab menu and to the archived notice (copy at `agent_chat_footer.dart:112` changes); mobile adds an entry on the workspace tabs screen. Mobile reopen uses a stable request id per chat like desktop's `AgentChatReopenIds`.

### J2. Choose provider, model, and modes in the composer

Target: one chip shows the provider mark and the model label (or provider label for the provider default) and opens an `AleraPopover` holding an `AleraSectionedPicker`: one section per enabled instance, one row per visible model, search across all, arrow keys, Enter, Escape, current pick on `AleraActiveRail`, unavailable instances as rows with their reason, and an Open Provider Settings footer. A new presentational `AleraProviderModelPicker` with a co-located preview carries this. Selection logic (grouping, filtering, default resolution, configuration building) lives once in `packages/alera_agent_chat`.

- Before the first message: one pick sends one `configure` with instance and model, no confirmation, no process start.
- After the first message: a provider pick shows one confirmation that explains the handoff; the new process starts with the next send. A model pick never confirms.
- While busy: provider rows are disabled with the `canSwitchProvider` reason; a model pick is held as a pending label and sent with the next message through `send.model` (the field exists, `agent_chat_inputs.dart:57`).
- Loading, offline, or failed catalog: the chip shows the chat's own provider and model, disabled, with Retry; the footer does not jump.
- Approval mode and Plan stay as chips; below a compact width token they fold into a "More Composer Controls" overflow with the picker and Send always visible. Full Access asks for confirmation on desktop and phone with the shared confirm dialog.
- Effort chip appears only when the selected model reports `reasoningEfforts`; it stays hidden until the runtime supports effort.
- Keyboard: a new registry action Choose Model on `Mod+Shift+M` (free today; `allowInTerminal: false`), dispatched to the active chat; `landing/src/data/keyboard-shortcuts.ts` changes in the same change. Do not copy T3's `Mod+Shift+A` or `Mod+Shift+E`, which are taken.
- Terminology: controls say Agent and Model; the Settings section explains "Agents for Agent Chat tabs. For terminal tabs, use Agent Profiles."

### J3. Send, queue, steer, stop

Current: every send uses `delivery: auto` (`agent_chat_controller.dart:292`), steer is never offered, desktop queue only removes, mobile queue edits, Escape stops a running turn.

Target: Enter keeps `auto`. When `session.capabilities.steer` is true, Mod+Enter sends with `steer` and the Send tooltip says which action applies. Desktop adopts `AleraMessageQueue` with Edit and Remove. Promoting an already queued message to a steer stays disabled because it would be two requests that can half fail (mobile comment, `mobile/.../agent_chat_footer.dart:52-54`); it needs an atomic host verb. Escape first closes an open popover or dock focus, and only then stops the turn. The phone offers steer from a long press on Send when supported.

### J4. Follow a turn

Target turn grammar, computed in the shared projection so both apps match:

| Turn state | Shows |
| --- | --- |
| Running | Prompt, "Working for Ns", one live row with the current action in present tense and a clamped first sentence of the latest reasoning, "N earlier actions" disclosure, narration inline, answer streaming below |
| Running, last action failed | Live row reads "Thinking"; failed action reachable through the disclosure |
| Settled, succeeded | "Worked for X" folded, answer, meta row (copy, time, origin caption), "Changed Files (N)" from the turn's `file_change` items |
| Failed, stopped, cancelled, interrupted by restart | Unfolded, existing label ("Failed after X", "Stopped after X"), failing action in error tone |

- Scroll: per-chat modes following, anchoring a new turn, and free. Any user scroll switches to free; following re-arms within 40 px of the end; on send the prompt anchors near the top until tool activity starts. Store offset, anchor, mode, and expansion overrides per chat in a session-only provider so tab switches restore them. Label the pill "Scroll To End" and show "Approval Needed" on it while a request is pending.
- Messages: meta on hover or keyboard focus, excluded from focus and hit testing while hidden; user messages collapse past 8 lines or 600 characters with Show Full Message; reasoning reads "Thought" once finished; user bubbles use a width fraction instead of a fixed inset on narrow panes.
- Accessibility: disclosures expose expanded state; a live region announces a new request, turn completion, and failures once per transition.

### J5. Answer questions, approvals, and plans

Target: approvals, MCP elicitations, and questions share one request dock above the composer with "Request X of N" paging. Priority inside a chat: approvals first, then elicitations, then questions, oldest first within each. Approvals offer exactly the runtime's `decisions` in its order, two primary buttons and the rest in an overflow. The composer stays mounted and keeps its draft; its hint becomes "The agent is waiting for your decision." A typing guard delays focus takeover until 1.5 s after the last keystroke, a send, or blur. The dock is capped at half of a narrow pane. No global key accepts an approval. Plan progress docks on both surfaces, and a proposed plan offers Implement In New Workspace, which prefills the delegate form. Desktop and mobile share request titles and decision labels from one package file (today they drift: "Allow Once" against "Allow", "Resume Session" against "Resume").

Not now: a durable "Allowed once" record after the request resolves. Request rows are pending-only, so this needs an additive runtime projection.

### J6. Usage, limits, recovery, reconnect

Target: desktop gains a usage popover from the context ring showing `usage.windows` with reset times (mobile already has a sheet). A notice stack above the composer orders action error, recovery, reconnecting, pending request, queue, plan progress. Errors clamp to three lines with full text on demand. A chat whose provider was disabled or removed shows the existing `providerUnavailable` or `providerMissing` recovery plus Open Provider Settings. A failed first start keeps the sent message and offers Resume or Start New Session; Retry stays deduplicated by `clientMessageId`. No "resume at reset": the runtime has no such capability.

### J7. Configure providers and models

Target: Settings, Resources, Providers, following the Agent Profiles master-detail pane. Header: host chips (This Device and each connected Remote Host, defaulting to the active workspace's host) and Refresh with "Checked 2m ago". Rows: agent mark, label, version, status line (Ready, Not Installed, Setup Required, Sign-In Needed, Unknown Sign-In, Error, Checking, Off), enable switch. Detail sections: Identity, Setup, Launch, Environment, Models, plus Default For New Chats.

- Status vocabulary must stay honest: sign-in reads Ready only from a verified CLI auth status or a successful bounded authenticated probe, cached with its `checkedAt`; otherwise it reads Unknown. Credential files alone are not proof. Claude has a verified signal the quota reader already runs (`claude auth status --json`, `agent_quota/claude.rs:170-189`, which reads `loggedIn`); Codex already has a bounded authenticated usage request (`agent_quota/codex.rs:14-49`), so its successful result can supply a checked signal, whereas reading `auth.json` alone cannot. A failed usage request does not by itself prove sign-out because network, service, and permission failures must remain distinguishable.
- Models: source label (Discovered, Configured, Provider Default Only), filter, counts, Hidden From Picker, order, Add Custom Model. Until host discovery ships, configured and custom model lists replace discovery; a failed discovery never blocks chat creation with the provider default. Claude has no list command, so it shows the provider default plus custom models.
- Secrets: write-only fields that show Saved with Replace and Clear, stored through `native_credential_entry` with the 0600 fallback pattern already used by `voice_credentials.rs` and `alera_account/credential_store.rs`, registered with `register_secret`, never returned, logged, or synced. No new vault.
- Sign In, Install, Update run the adapter's verified command in the command terminal, then re-check status.
- Removing a custom instance shows impact first (open chats that will need a switch), like `agentProfile.removalImpact`.

### J8. Delegate, message, and attend across chats

Target inside a chat: a Tasks dock replaces "Delegated Tasks" (`chat_task_notice_views.dart:89-135`). Collapsed: "Tasks · 2 running · 1 needs input · 3 done". Expanded rows: provider mark, title, place label (project / workspace · host), status, elapsed time, and on hover or focus Stop and Open Chat; View In Activity routes to detail. A child-input banner ("Task needs input: <title>", Answer Here, Open Chat) appears above the dock unless the parent has its own pending request. A child chat shows "Delegated by <parent>" or "Delegated by you" with Open Parent, and its brief renders expanded and labelled Task (today a human-delegated brief says it came from another chat). Wakes render as one response boundary with one outcome card per task. A chat header overflow adds Delegate Task and Send To Chat, defaulting to this chat as parent and "New Chat in This Workspace"; the delegate form reuses the composer picker.

Attention: tab dots gain Waiting On Tasks (needs input > failed > working > waiting on tasks > idle). Sidebar workspace attention includes chats (today it reads terminal `AgentStatusEntry` only). Desktop shows a toast with Open Chat when focused elsewhere, or an OS notification when unfocused, once per transition, for non-child chats; children report through their parent. Unread "done" uses a host read cursor so phone and desktop agree. Activity remains the only cross-chat hub: no new overlay, chip, or shortcut, and Wait For Result moves to an overflow. No arrival ever navigates.

### J9. Phone parity

Target: the phone uses the same direct create, the same default resolution, the same switch and confirmation rules, the same request dock and labels, Full Access confirmation, steer when supported, queue Edit, the Tasks dock, and the child-input banner, with mobile-native presentation (tune sheet with search and models grouped by provider, reversed list, always-visible meta). Phone settings: Host Settings, Manage, Providers with the permissions in the table below. Mobile Chat Tasks dock and origin notice parity is inferred from matching names (`ChatTaskDockView`, `ChatTaskOriginNotice` under `mobile/lib/src/features/chat_tasks`); verify before claiming it in docs.

### J10. Archive, reopen, and history operations

Target now: close of a never-sent chat discards it instead of archiving it; archived chats reopen from the new entry points. Later and separate: fork from a response, rewind to a turn with its prompt back in the composer, delete from the archive, edit-and-resend of a settled message. Session capabilities already declare `fork` and `rollback` per adapter, but no verbs exist (`readme.md` verb table). Each needs host design across all providers and the handoff.

## Architecture, Wire, and Storage

All additions are additive behind capabilities advertised in the control file, `status.get`, and `MOBILE_HELLO_CAPABILITIES`, and none bumps `aleraTerminalHostProtocolVersion` or the mobile protocol version. New events go in `runtimeHostEventNames`.

### Deferred native start (`agentChatDeferredStartV1`)

- `create` stops calling `ChatOp::Recover` (`runtime_handle.rs:344-346`) and keeps validating the instance and traits as today unless `agentChatUnselectedDraftV1` applies. The header stays `session.status: stopped` with no recovery. The first `send` starts the provider through `plan_start` and the deferred turn.
- `configure` with a new instance closes any old process and never starts the new one (`session_config.rs:58` goes); the next send starts it, with the handoff when `has_items`. The readme sentence "No model is called until that send" becomes true for the process too.
- `recover` on a never-sent chat returns the snapshot without starting anything, so older clients that call it do no harm.
- The header gains `titleSource: default|derived|user` so derived titles never overwrite a rename.
- `close` on a chat with no items and no turns deletes the record and tab instead of archiving and returns `{archived: false, discarded: true}`; the store gains a delete for that case only. The never-sent check and the delete run in one actor step, so a `send` the actor ordered first wins and the close archives instead; `close` is receipt-backed by `requestId`, so a retry returns the same result. Because another client may hold unsent text the host cannot see, a client whose chat is discarded elsewhere while its own draft is non-empty keeps that text and shows a notice with Copy and Start New Chat With This Text, without navigating.
- Never-sent is derivable from the snapshot (no turns, no items, no native thread), so clients need no new status value.
- Effects on chat orchestration are not proven by source reading. `ProviderLaunchHook` should still run before each native spawn and delegated chats send at once, but Phase 1 must add regressions for credential injection on a deferred first start, delegation into a never-sent chat, and cancellation or close while the deferred startup is in flight.

### Model selection

- Catalog: Dart keeps `AgentChatModelOption.id` nullable; `null` means provider default and is never coerced to `''`.
- `create` and `send`: a provider-default choice omits `model`.
- `configure`: the readme documents `model: null` as "reset to the instance or provider default", matching current host parsing. Dart represents this with an explicit reset choice rather than a nullable string, so omission and reset stay distinct. An empty string remains tolerated on the host for older clients but no client sends it.

### Host preferences (`agentChatPreferencesV1`)

A per-runtime store row, not `runtimeSettings`, because whole-object updates would let desktop and phone overwrite each other. Shape: `{rememberedSelection?, defaultSelection?, projectDefaults{projectId: selection}, models{instanceId: {hidden[], order[]}}, favorites[], revision}` where a selection is `{providerInstanceId, model?, runtimeMode?, interactionMode?}`. Verbs `agentChat.preferences.get` and `agentChat.preferences.update` with per-entry operations and `expectedRevision`. The host writes `rememberedSelection` on a successful first send. Event `agentChatPreferencesChanged`.

### Provider instance store (`agentChatProviderSettingsV1`)

- Table of instance envelopes `{instanceId, provider, label?, enabled, executable?, args[], environment[{name, sensitive}], options{}, customModels[], revision}`. Default instances become optional override rows; a missing row means defaults.
- Verbs: `agentChat.providerInstances.upsert`, `remove`, `removalImpact`, `secrets.set`, `secrets.clear`, all receipt-backed with `requestId` and `expectedRevision`.
- Event `agentChatProvidersChanged {hostId?}`; the composer catalog and Settings invalidate on it.
- One-time import of valid `agent-chat-providers.json` entries while the store is empty: every env value becomes sensitive, secret options move to the keyring, the file is renamed `.imported`, and an invalid file is left in place and reported without contents.
- Secrets reach only `hydrated_environment` and the launch builder (`production_factory.rs:143-163`).

### Status cache and discovery

- Stage A: a per-host snapshot with `checkedAt`; `agentChat.providers` answers from cache and refreshes in the background when stale; `refresh: true` forces it. This removes today's per-call availability probes, each of which hydrates the login-shell environment.
- Stage B: `installed`, `version` from a bounded probe, `auth {status: signedIn|signedOut|unknown, label?, checkedAt}` set only from a verified CLI auth status or a successful bounded authenticated probe, and verified `setup` commands.
- Stage C: implement `discover_models` in the production factory from existing primitives (OpenCode and Cursor SDK listings; Codex, Pi, and Antigravity CLI listings already proven in `ai_assist_registry.dart`, ported to Rust and run on the target host). One host discovery service later serves Agent Profiles and AI Assist too.

### Reasoning effort (`agentChatEffortV1`)

Per-model `reasoningEfforts` and `defaultReasoningEffort` in the catalog, `reasoningEffort` on `create`, `configure` (with explicit reset like model), and `send`, mapped through `SessionStartInput.options` per adapter. An adapter that cannot honor it answers `unsupported`, shown above the composer. Until this ships, no effort UI appears.

### Attention data

Additive `openChildTaskCount`, `childNeedsInput`, and `unread` on `agentChat.list` summaries; one runtime-wide chat activity provider reads `agentChat.list` without a workspace id. Read state is a host cursor per chat set by `agentChat.markRead {chatId, cursor}`.

### Permissions

The model distinguishes authenticated humans from less-trusted callers instead of banning remote human administration. A paired phone is an authenticated human client: it can already run `agentChat.configure` including Full Access, create and attach terminals, launch Agent Profiles, and save voice credentials write-only (`mobile_gateway_surface.rs:151-178`, `:233-235`, `:301`, `:349-352`). A satellite is less trusted: `agentChat.` is a denied prefix in the reverse policy (`hub_reverse_policy.rs:19`). Chat-bound agent credentials act only in their own lineage.

| Action | Desktop | Paired phone | Hub acting on its satellite | Satellite reverse channel | Chat-bound agent |
| --- | --- | --- | --- | --- | --- |
| Chat control (create, send, configure, respond, interrupt, recover, close, reopen) | Yes | Yes (already allowlisted) | Yes, forwarded | Denied | Own lineage only |
| Read status, catalog, preferences; Refresh | Yes | Yes | Yes | Denied | Catalog read only |
| Enable or disable instance, defaults, model visibility and order, custom model ids | Yes | Yes | Yes | Denied | Denied |
| Set or clear a declared secret value (write-only) | Yes | Yes, like voice credentials | Yes | Denied | Denied |
| Sign In, Install, Update in a PTY | Yes | Deferred (inferred feasible through terminals) | Yes if the command terminal can target the host (unverified) | Denied | Denied |
| Launch definition (executable, args, env names and non-secret values, add or remove instance) | Yes | v1 no, see decision 3 | Yes | Denied | Denied |

The v1 phone restriction on launch definitions is a consistency choice, not a security absolute: the phone cannot edit Agent Profiles today and `aiAssistSettings` custom commands are refused from non-local clients (`remote_ai_assist_requests.rs:79-99`). Phone chat-control parity is complete without it.

## Performance Constraints

- The host already coalesces streamed text for 50 to 100 ms or 8 KiB per chat (`readme.md`); clients keep applying deltas by cursor and never re-read snapshots per token.
- Settled turns render as immutable widgets keyed by turn id; only the running turn and explicitly expanded rows rebuild. A running turn builds one live row plus expanded rows, not every action.
- Elapsed timers update through a narrow listenable per header, not a parent rebuild.
- The timeline stays lazily built with anchored scroll; diffs and long outputs render lazily with line caps; tool input and result JSON is formatted once per item, off the UI isolate when large.
- Streaming must not request a frame per vsync on Linux (AGENTS Flutter Performance). Measure with an `integration_test` benchmark before and after per `docs/performance.md`.
- Provider status comes from the host cache, so opening Settings or the composer never probes providers more often than the TTL.

## Phases

Each phase is shippable alone, feature-detected, and updates `docs/agent-chat.md`, the runtime `readme.md`, shortcut data when a shortcut changes, and the CLI and MCP skills when a verb changes.

### Phase 1. Deferred start and wire fidelity (runtime and package)

Scope: deferred native start, `titleSource`, discard of never-sent chats, explicit model reset, nullable model ids in Dart, stable mobile reopen ids.

Acceptance: (1) a Rust test asserts `create` performs zero factory spawns and the snapshot is `stopped` without recovery, and after a host restart clients show the ready empty state, not a stopped banner; (2) the first `send` starts the provider and delivers that message as turn one; (3) a provider switch on an empty chat and on a chat with history spawns nothing until the next send, and the next send on the latter carries the handoff; (4) closing a never-sent chat leaves no archived entry and no record; (5) `configure {model: null}` resets to the default and a Dart unit test proves no request ever carries `model: ""`; (6) a derived title appears after the first send and never overrides a rename; (7) a failed first start keeps the message and recovers without duplicates; (8) credential injection, delegation into a never-sent chat, and cancel or close during deferred startup behave as before; (9) a close racing a send never loses the sent message, and a repeated close returns the same receipt. Expect `startup_cancellation_tests.rs` and `production_factory_tests.rs` to need updates.

### Phase 2. Direct open and composer picker (desktop and phone)

Scope: remove the dialog and sheet, default resolution from the package (session-local until Phase 3), combined picker, conditional confirmation, loading state, compact overflow, Full Access confirmation, archived entry points, `Mod+Shift+M`, shared labels.

Acceptance: (1) widget tests show `Mod+Shift+T` and add-tab open a focused chat with no dialog and no workspace switch, and a tab created after the person moved away is persisted but not selected; (2) a repeated New Agent Chat focuses the existing never-sent chat; (3) picking a model under another provider sends one `configure`; (4) empty chats switch without a dialog, chats with history confirm once, busy chats disable provider rows with a reason; (5) the picker is fully keyboard operable and Escape closes it without stopping a turn; (6) at 360 px the picker and Send stay visible with no horizontal scroll; (7) the same rules pass in a mobile widget test; (8) the keyboard and landing fidelity tests pass.

### Phase 3. Host preferences and Providers settings

Scope: preferences store and event, status cache, and the Providers pane on desktop and phone. Preference edits are writes in this phase: Default For New Chats, project defaults, and model visibility and order; Refresh forces a status re-check. Provider launch details (executable, arguments, environment, secrets, enable switches) stay read-only until Phase 5.

Acceptance: (1) a default chosen on desktop is used by the next New Agent Chat on a paired phone within one event and survives app and host restarts; (2) precedence tests cover project, launching chat, explicit default, remembered, and first enabled and available, including skipping disabled instances; (3) repeated catalog reads within the TTL run no probes; (4) hidden models are absent from the picker while a chat's current hidden model stays selectable.

### Phase 4. Transcript, request dock, usage

Scope: turn grammar, scroll model and session state, request dock with typing guard and priority, notice stack, desktop usage popover, message polish, accessibility, lazy details.

Acceptance: (1) a 50-action running turn shows one live row and a benchmark shows no rebuild of settled turns per delta; (2) failed, stopped, cancelled, and restart-interrupted turns render unfolded; (3) a pending approval appears in the dock on both surfaces with every runtime decision in order and the draft intact; (4) a request arriving within 1.5 s of a keystroke does not move the caret; (5) tab switches restore scroll and folds; (6) labels are identical across surfaces.

### Phase 5. Provider settings writes and secrets

Scope: instance store, import, upsert and remove with impact, keyring secrets, enable switches, custom models, permission table enforcement, hub forwarding by `hostId`.

Acceptance: (1) an edit on desktop updates an open picker on desktop and phone within one event; (2) no secret appears in any response, event, log, or diagnostics bundle; (3) phone writes to launch definitions are refused and phone secret saves succeed; (4) satellites cannot reach any of these verbs; (5) importing an existing file keeps every valid instance and the chats using it.

### Phase 6. In-chat tasks and attention

Scope: Tasks dock, child-input banner, parent link and Task brief, wake outcome cards, Delegate Task and Send To Chat entry points, waiting-on-tasks dot, chat sidebar attention, read cursor, desktop toast and OS notifications.

Acceptance: (1) none of these actions changes `activeWorkspaceId` except an explicit Open Chat or Open Workspace; (2) a child approval raises the parent banner within one `chatOrchestrationChanged` and Answer Here resolves it in place; (3) notifications fire once per transition and never navigate; (4) a human-delegated brief never says "another chat"; (5) without `chatOrchestrationV1` every surface is hidden and Activity shows Update Required.

### Phase 7. Additional design and runtime phases

These need further design before code, not a separate approval: this document is analysis only, and a future implementation authorization can cover the whole scope including this phase. Required by the accepted Settings requirement: host model discovery and verified auth status (Stages B and C). Further extensions: reasoning effort, atomic promote-to-steer, phone Sign In, approval history projection, per-turn diff, chat push notifications, fork, rewind, delete, and provider-native subagent lineage. Each design covers all adapters, the handoff, recovery, and phone parity.

## Unsupported or Intentionally Different

- Provider lock after the first message (Alera keeps handoff switching).
- Client-only drafts and multi-model drafts.
- Worktree and branch pickers in the composer (the workspace owns them; delegation chooses a target workspace).
- Wake steering into an active parent turn: current Alera behavior delivers wakes only to an idle parent with no pending request, and this proposal retains it (Open Decision 7).
- Resume at usage reset, accent colors, project-scoped enable overrides, a provider auto-update scheduler, and an ACP registry browser.
- Import of legacy Codex tabs.
- Any automatic navigation from background events, and any second cross-chat overlay, chip, or shortcut next to Activity.
- An effort selector before the runtime contract supports effort.

## Open Decisions

1. Never-sent chats on close: discard (recommended) or archive and hide. Discard mirrors T3's draft discard and keeps the archive meaningful; it is atomic on the host, and other clients keep their unsent text as described under deferred start.
2. Remembered selection versus explicit default: recommended precedence is project default, launching chat, explicit default when set, remembered last send, first available. The alternative drops the explicit default and relies on remembered only, like T3.
3. Phone editing of launch definitions: recommended no in v1, matching Agent Profiles; revisit both together. The alternative is a desktop-set host toggle that allows paired phones to edit them.
4. Chat push notifications: recommended in-app only first; push needs an additive kind and cloud work with state and names only.
5. Read state: recommended host cursor shared by all clients; the alternative is per-device local state.
6. Provider-native subagents as lineage rows: recommended deferred, showing app-owned tasks only.
7. Wake delivery: recommended keep the current idle-only delivery. The alternative is T3-style steering into an active parent turn when the adapter supports steer; the no-auto-navigation requirement does not decide this.

## Sources

Source reviews consolidated: `ux_chat_journeys.md`, `ux_composer_full.md`, `ux_timeline_requests.md`, `ux_provider_settings_deep.md`, `ux_tasks_attention.md`, `ux_end_to_end_consistency.md`. Corrections made against source: create is eager (one review said otherwise); the phone new-chat sheet has Agent and Model only (one review said it matched desktop); the host already accepts an explicit model reset on `configure` but no client can send it; queued-message steering is blocked for atomicity while send-time steer is supported; the phone already holds human administration precedents (Full Access, terminals, voice credentials), so a blanket phone ban on Settings writes is not justified.
