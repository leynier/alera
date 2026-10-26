# agent chat runtime

Runtime-host chat sessions over the Rust provider adapters (`alera-provider-*`). The host owns every provider process and persists the transcript, so a chat survives the app closing and is driven identically from desktop and paired phones. Chats coexist with terminal tabs.

## Capability and tab kind

- `agentChatV1` is advertised in the control file, `status.get` and `MOBILE_HELLO_CAPABILITIES`. It is additive and does not bump `aleraTerminalHostProtocolVersion` or the mobile protocol version.
- A client opts in by sending `supportedTabKinds: ["agentChat"]` in `hello` (local) or `mobile.hello`. Clients that do not declare it never see `agentChat` tabs in `tab.list`, `tab.find` or tab events, cannot `tab.upsert` over one and cannot `tab.remove` one, and never receive `agentChat*` events.
- Tab record: `kind: "agentChat"`, `payload: {chatId, provider, providerInstanceId, model?}`, `title` = chat title. The payload keys are host-owned: a client `tab.upsert` keeps the stored values.
- `tab.remove` of an `agentChat` tab uses the same lifecycle as `agentChat.close`: a never-sent chat is discarded atomically; a chat with history is archived, its provider stopped and queued input cancelled.
- `agentChatApprovalRedirectV1` adds `declineRequests: {requestIds}` to `agentChat.send`: the pending approvals the sender saw. In one actor step the runtime declines them (or cancels where decline is not offered) and admits the message. When the pending approvals are not exactly those, it refuses with `errorCode: "approvalsChanged"` before declining anything. The CLI and MCP send surfaces do not expose it.
- Native verbs use `agentChatNativeRewindV1`, `agentChatRewindFilesV1`, `agentChatFileCheckpointsV1` and `agentChatNativeHistoryV1`. Global wire support is separate from the session's verified native capabilities and exact available boundaries.

## Verbs

Every mutation carries a client `requestId` (string, unique per caller). The receipt key is `(callerScope, verb, requestId)`; `callerScope` and the actor come from the connection (`desktop`, `cli`, `mobile:<deviceId>`), never from the payload. A replay with the same payload digest returns the stored response; a different payload returns `errorCode: "request_conflict"`. Chat-scoped verbs SHOULD also carry `workspaceId` (routing for remote workspaces).

| Verb | Payload | Result |
| --- | --- | --- |
| `agentChat.providers` | `{workspaceId?, refreshModels?}` | `{providers: [Provider]}` |
| `agentChat.list` | `{workspaceId?, includeArchived?}` | `{chats: [ChatSummary]}` |
| `agentChat.create` | `{requestId, workspaceId, provider?, providerInstanceId?, model?, reasoningEffort?, runtimeMode?, interactionMode?, title?}` | `{chatId, tabId, snapshot}` |
| `agentChat.reopen` | `{requestId, chatId}` | `{chatId, tabId, snapshot}` (archived chat gets a new tab) |
| `agentChat.snapshot` | `{chatId}` | `Snapshot` (items bounded to 256 KiB) |
| `agentChat.history` | `{chatId, before, limit?}` | `{items, turns, historyBefore?}` (bounded to 256 KiB) |
| `agentChat.payload` | `{chatId, workspaceId?, itemId, index?:0, limit?:200}` | `{chunks:[{index,text}], nextIndex?, segmentCount, format:"json", revision}` (bounded to 256 KiB) |
| `agentChat.send` | `{requestId, chatId, clientMessageId, text, attachments?, delivery?: auto\|steer\|queue, model?, reasoningEffort?, interactionMode?, declineRequests?: {requestIds}}` | `{delivery: started\|queued\|steered, itemId?, turnId?, queueId?}` |
| `agentChat.queueCancel` | `{requestId, chatId, queueId}` | `{cancelled: bool}` |
| `agentChat.queueEdit` | `{requestId, chatId, queueId, text}` | `{updated: true, queueId}` (attachments preserved) |
| `agentChat.queueReorder` | `{requestId, chatId, queueId, index}` | `{reordered: bool, queueId, index}` (`agentChatQueueReorderV1`; an index past the end lands on the last slot) |
| `agentChat.queueSteer` | `{requestId, chatId, queueId, turnId}` | `{delivery: steered, queueId, itemId, turnId}` |
| `agentChat.interrupt` | `{requestId, chatId, turnId?}` | `{acknowledged: true}` (the turn ends through events) |
| `agentChat.respond` | `{requestId, chatId, runtimeRequestId, response}` | `{resolved: true}` |
| `agentChat.configure` | `{requestId, chatId, provider?, providerInstanceId?, model?, reasoningEffort?, runtimeMode?, interactionMode?}` | `{snapshot}` |
| `agentChat.rename` | `{requestId, chatId, title}` | `{title}` |
| `agentChat.recover` | `{requestId, chatId, mode?: resume\|restart}` | `{snapshot}` |
| `agentChat.close` | `{requestId, chatId}` | `{archived: bool, discarded?: bool}` |
| `agentChat.fork` | `{requestId, chatId, turnId, title?}` | `{chatId, tabId, snapshot, operationKind, filesystemChangesReverted: false}` |
| `agentChat.rewind` | `{requestId, chatId, turnId, mode?: transcript\|native}` | `{snapshot, prompt, attachments, promptItem, operationKind, nativeRollback, filesystemChangesReverted: false}` |
| `agentChat.rewindFiles` | `{requestId, chatId, turnId}` | `{snapshot, operationId, filesystemRewindAcknowledged, filesystemChangesReverted: bool\|null}` |
| `agentChat.fileCheckpoints.configure` | `{requestId, chatId, enabled}` | `{snapshot}` |
| `agentChat.nativeHistory.operation` | `{chatId, operationId?}` | `{operation: null\|{operationId, state, kind, recovery?}}` |
| `agentChat.nativeHistory.reconcile` | `{requestId, chatId, operationId, expectedRevision?, action}` | `{snapshot, operation: {operationId, state, kind}, result?}` |
| `agentChat.delete` | `{requestId, chatId}` | `{deleted: true}` (archived chats only) |
| `agentChat.approvalHistory` | `{chatId, before?, limit?}` | `{items, historyBefore?, scanLimited}` |
| `agentChat.turnDiff` | `{chatId, turnId}` | `{turnId, source: provider, available, items, truncated, reason?}` |
| `agentChat.markRead` | `{requestId, chatId, cursor}` | `{cursor, readCursor}` (no snapshot cursor change) |

`send` with `delivery: auto` starts a turn when idle and queues behind a running turn; `steer` is accepted only when the session capability `steer` is true (`errorCode: "unsupported"` otherwise). `clientMessageId` is idempotent on its own: resending it returns the original result.

`respond.response` is one of `{type: "approval", decision}`, `{type: "userInput", answers: {questionId: value}}`, `{type: "elicitation", action, content?}`, `{type: "native", result}`. `runtimeRequestId` is the runtime's id; the provider's native id never leaves the host. The first writer wins: a later answer gets `request_resolved`. A decision outside the request's `decisions` gets `unsupported`.

`configure` changing `provider`/`providerInstanceId` is accepted only while idle with no open requests and no queued or background work (`errorCode: "turnActive"` otherwise). It keeps every earlier turn and item (each carries its generation's provider) and closes the old process. The next send starts a native session and carries a bounded quoted transcript of prior user and assistant text (no reasoning, no tool payloads). Creation and provider changes spawn no process. `configure.model: null` explicitly resets to the instance or provider default; omitting `model` preserves the current selection. The empty string is accepted only for older clients. A change the provider cannot honor returns `unsupported`.

## Additive lifecycle contract

`agentChatDeferredStartV1` means creation persists the chat and its tab with `session.status: stopped` and no recovery. A never-sent chat has no items, turns or native session; `recover` on it is a snapshot read. Its first send commits the prompt before provider startup, runs every launch hook before spawning and derives `title` from the first non-empty prompt line, trimmed to 200 characters. `titleSource: default|derived|user` prevents an automatic title from overwriting a rename. Switching a never-sent chat relabels only an untouched default title.

`agentChatUnselectedDraftV1` permits creation without a selection. Public `provider` and `providerInstanceId` are null; the store's internal sentinel is never presented as an agent. `send` answers `providerRequired` until configure sets the first selection. No native process or recovery runs for an unselected draft. Close checks durable items, turns, native identity, pending requests, queue and task linkage before discard; the detached close receipt survives deletion so a retry returns the same result.

`ChatOp::QueuePromoteToSteer {queue_id, turn_id}` backs `agentChat.queueSteer`. The live provider must support native steering and the supplied app turn must still be active. The actor keeps the queued entry until the provider accepts `steer_turn`; rejection leaves it intact. Accepted steering records a user item in the existing turn, without starting another turn. Steering cannot alter the active turn's model or effort, or bypass a pending request or the caller's runtime mode ceiling.

`CreateChatInput.reasoning_effort: Option<String>`, `ConfigureInput.reasoning_effort: Option<Option<String>>` and `SendInput.reasoning_effort: Option<String>` preserve omission versus explicit reset. Effort is validated against verified model metadata before a change or message is accepted. The canonical adapter option is `reasoningEffort` in both `SessionStartInput.options` and `TurnInput.options`; the adapter owns conversion to its native fields. Unsupported adapters reject it rather than silently dropping it. Changing models resets an omitted effort, and explicit null on configure clears it. The selected model is sent on every supported per-turn model boundary; resetting to a provider default restarts an idle configured process on the next send, avoiding its old launch model.

History operations distinguish host transcript changes from native history. `fork` copies the full durable prefix through a settled turn into a new stopped chat. Its `operationKind` is `transcriptFork` unless a live provider proves an exact native turn boundary in the current generation, in which case it is `nativeForkDeferred`. Native fork intent stays host-only; the target's first send runs its launch hooks and calls `fork_session` on a fresh connection. It never forks the latest native turn as a substitute for the selected one. The target adopts only a provider-observed native identity. Transcript forks start with the normal handoff.

`rewind` defaults to transcript mode: it removes the selected turn and every later turn, restores its complete prompt and attachments, cancels removed message ids and resets native identity in a new generation. It returns `operationKind: transcriptRewind` and `filesystemChangesReverted: false`; the next send carries the retained transcript. A turn with additional steering messages is refused before any native call instead of dropping those messages from the restored composer. Native mode uses a verified `rollbackBeforeTurn` capability and an exact native turn mapping in the current process epoch. Count-based legacy rollback is not used. Archived deletion refuses active task or native operation linkage and retains settled task lineage.

Native rollback and file rewind save a durable intent and execution CAS before provider I/O. Verified acknowledgment is saved before the store commits the requested history change. A timeout, provider error, mismatched identity or ambiguous acknowledgment freezes the operation; neither restart nor request replay calls the provider again. `pendingNativeOperation` is a sanitized snapshot and delta field; explicit null clears it. Its recovery object has `needsReconciliation`, `canCancelUnstarted`, `canFinishAcknowledged`, `canRestartFromTranscript`, `canContinueFromCurrentFiles` and a fixed `message`. No native IDs, acknowledgment bodies, receipt scopes or provider errors appear there. Pending mutations return `nativeOperationPending` or `nativeOperationUncertain`; a failed revision CAS returns `nativeOperationRevisionConflict`.

Explicit reconciliation actions are `finishAcknowledged`, `cancelUnstarted`, `restartFromTranscript` for uncertain conversation rewind and `continueFromCurrentFiles` for uncertain file rewind. Acknowledged completion retains the provider-observed native context; explicit fallback clears it and resumes later through transcript handoff. Reconciliation never repeats a native call. Unresolved operations keep the host busy and block send, configure, archive, delete and task admission. Reads and graceful shutdown remain available.

`session.fileCheckpointing` is the enabled launch setting; `session.capabilities.nativeHistory.fileCheckpointing` is adapter support, and `rewindFiles` is actual launched support. Enabling or disabling checkpointing is idle-only and takes effect at the next provider launch. Claude receives `SessionStartInput.options.enableFileCheckpointing` and a host-only `TurnInput.options.appUserItemId`. Only a validated original main-prompt USER UUID is mapped onto that app item and turn; assistant UUIDs, synthetic IDs, uncorrelated echoes and tool results cannot become file rewind boundaries. Native file rewind preserves conversation history. `filesystemRewindAcknowledged` records the verified native response; `filesystemChangesReverted` remains null without explicit native changed-file observations. Conversation rewind always reports false for filesystem changes.

Approval history records pending, resolved, providerResolved and expired states with the exact accepted decision, actor and time. It excludes user-input answers, elicitation content and native results. Per-turn diffs use only provider-reported diff or file-change fields, redact sensitive keys and retain oversized exact data behind existing payload paging. Unavailable, incomplete or truncated data is reported explicitly. Neither operation infers file changes from output text. Read cursors are shared by host clients and receipt-backed without changing the transcript cursor.

Error codes (`errorCode` next to `error`): `request_conflict`, `request_resolved`, `unsupported`, `turnActive`, `turnNotActive`, `chatNotFound`, `chatArchived`, `providerUnavailable`.

## Events

- `agentChatChanged {chatId, workspaceId, cursor, delta}`. Every persisted change increments `cursor` by exactly one and is committed before it is broadcast. A client that sees `cursor > known + 1`, or reconnects, reloads `agentChat.snapshot`. Changes with `cursor <= known` are stale and ignored.
- `agentChatsChanged {workspaceId?}`: the chat list changed (create, close, reopen, rename, provider switch).
- `workspaceTabsChanged` as for any tab create, remove or rename.

Streamed text is coalesced for 50 to 100 ms or 8 KiB per chat and flushed on item completion, turn end and before any snapshot.

Large redacted native data is retained in hidden payload rows rather than discarded. Normal snapshots, history and public deltas omit those rows while every durable commit retains them and every public change keeps its cursor. `agentChat.payload` takes the visible head item ID and uses zero-based chunk indices. It is an explicit human read, including archived chats; credential-bound agents retain their orchestration-only allowlist. The optional Dart payload repository verifies contiguous chunks and a stable revision. A changed or incomplete payload returns an error so the person can retry instead of combining data from different versions.

## Shapes

`Snapshot {chatId, workspaceId, tabId, providerInstanceId: string|null, provider: string|null, title, titleSource: default|derived|user, archived, cursor, session, turns[], items[], pendingRequests[], queue[], usage?, recovery?, lineage?, historyBefore?}`

`session {status: starting|ready|running|waiting|stopped|error, model?, runtimeMode, interactionMode, activeTurnId?, cwd?, generation, capabilities {resume, interrupt, approvals, userInput, mcpElicitation, streaming, modelSwitch, steer, fork, rollback, attachments, images, plan}, errorMessage?}`. `runtimeMode`: `approval-required|auto-accept-edits|auto|full-access`; `interactionMode`: `default|plan`. With no turn running, a live session stays `running` while native background work the agent resumes from is still open (`task.*` events with `awaited: true`: native sub-agents, not background commands); it returns to `ready` when that work ends. A completed turn leaves such work open, and so does a failed turn whose provider reports `childTurnsContinue`; any other failed or stopped turn ends the work it started. This never holds the queue: the next queued message starts as soon as the turn ends. When a child whose `task.completed` carries `wakesParent` (a direct Codex sub-agent) finishes after the turn that started it completed, and nothing runs, waits on the user, starts or is queued, the runtime starts a parent turn whose `user_message` has `origin {kind: subagentWake, taskIds: [<task id>]}` and text `Subagent <completed|failed>: <label>` followed by the child's final answer (at most 64 KiB). A running or queued turn receives the result natively instead, so children finishing together resume the parent once; children of a turn that failed, was interrupted or was cancelled never resume it. Restart needs nothing extra: native children die with their provider process, and a resume already admitted is an ordinary durable turn.

`turn {turnId, status: running|completed|failed|interrupted|cancelled, startedAt, completedAt?, errorMessage?, failureClass?, reason?, model?, provider, providerInstanceId, generation}`. A turn cut short by a host restart is `interrupted` with `reason: "runtimeRestarted"`. `failureClass` (`usage_limit|context_window_full|auth|previous_turn_active|attachment_unreadable`) is set on a failed turn only when the provider's typed error says why; `errorMessage` always keeps the provider's own text.

`item {itemId, turnId?, type, status: inProgress|completed|failed|declined, streaming, createdAt, updatedAt, title?, detail?, text?, reasoningText?, output?, clientMessageId?, attachments?, actor?, normalized {command?, cwd?, exitCode?, durationMs?, changes?, toolName?, server?, input?, result?, query?, url?, imagePath?, planSteps?, explanation?, origin?, parentItemId?, subagent?}, data?}`. `parentItemId` names the tool call a provider-native sub-agent's item belongs to, and `subagent {status: running|completed|failed|stopped, taskId?, description?, summary?, taskType?}` on that call carries what the provider's task events reported. A `user_message` always has `normalized.origin {kind: user|chatMessage|orchestrationWake|subagentWake, senderChatId?, taskIds?}`; only host code sets a kind other than `user`. A `subagentWake` names provider task ids, not chat tasks. A turn whose prompt carries the transcript into a fresh provider session gets a `notice` with `normalized.handoff {from? {provider, providerInstanceId, model?}, to {provider, providerInstanceId, model?}, status: pending|completed|failed}`: it settles `completed` once the provider accepts the turn and `failed` when the turn ends first, and `from` is the source of the last handoff that failed, else the previous turn. `type` is snake_case: `user_message, assistant_message, reasoning, plan, command_execution, file_change, mcp_tool_call, dynamic_tool_call, collab_agent_tool_call, web_search, image_view, review_entered, review_exited, context_compaction, error, notice, unknown`.

`request {requestId, kind, turnId?, itemId?, createdAt, title?, detail?, command?, cwd?, path?, questions[], decisions[], elicitation? {mode, message, schema, url?}, expiresAt?}`. `kind` is snake_case (`command_execution_approval`, `file_change_approval`, `tool_user_input`, `mcp_elicitation_approval`, ...). `decisions` lists exactly what the provider accepts (`accept, acceptForSession, acceptAlways, decline, cancel`).

`delta {items?, removedItemIds?, textAppends? [{itemId, stream: text|reasoningText|output, offset, text}], turns?, requests? (the full pending list), queue? (the full queue), session?, usage?, title?, provider?, providerInstanceId?, archived?, recovery? (null clears)}`. `offset` counts UTF-16 code units of the field before the append.

`queue entry {queueId, clientMessageId, text, attachments?, createdAt}`.

`usage {tokens {input?, output?, cached?, reasoning?, context?, contextWindow?}, windows[]}`.

`recovery {kind: providerExited|resumable|notResumable|providerMissing|authRequired, message, canResume, canRestart}`.

`Provider {provider, providerInstanceId, label, available, unavailableReason?, custom, models [{id, label, isDefault}], modelsSource: discovered|configured|providerDefault, capabilities, runtimeModes[], interactionModes[]}`. When no cheap model discovery exists the list holds the configured model or a single `providerDefault` entry; nothing is invented.

`ChatSummary {chatId, workspaceId, tabId?, title, provider, providerInstanceId, model?, status, archived, cursor, readCursor, unread, openChildTaskCount, childNeedsInput, childFailed, parentChatId?, updatedAt}`. `parentChatId` names the chat whose first delegation handed work to this one, so clients can draw each chat's own delegation tree.

## Attachments

Attachment paths are host paths. Relative paths resolve against the chat's working directory. Mobile clients may only reference files returned by `mobile.promptImage.*` / `mobile.promptFile.*` uploads or files inside the chat's workspace; anything else is refused.

## Recovery and lifecycle

After a host restart, running turns become `interrupted` (`reason: runtimeRestarted`), open requests expire, and sessions become `stopped` with `recovery.kind` `resumable` when the generation has a native id and the adapter can resume, `notResumable` otherwise. Nothing is restarted until `agentChat.recover` or the next `send`; a non-resumable chat restarts with the transcript handoff. A provider process that dies marks the session `error`, expires its requests and records `providerExited`.

Host shutdown is deferred while any chat has a running turn, an open request or queued input. Idle chats behave like detached terminals. A real shutdown closes providers gracefully.

## Remote workspaces

For a workspace on a remote host the satellite owns the chat, its store and its providers. The hub forwards `agentChat.*` over the host link, mirrors the tab record and relays `agentChatChanged` / `agentChatsChanged`. No transcript is copied to the hub or the cloud.

## Provider instances

The nine providers are `codex`, `claudeAgent`, `cursor`, `grok`, `opencode`, `antigravity`, `pi`, `muse` and `acpRegistry`. Each has a default instance whose id equals the provider id. Further instances (other binaries, arguments, environment, custom ACP recipes) come from `<runtimeDir>/agent-chat-providers.json`; environment values are passed to the process only and never returned.

## In-process runtime handle

Chat orchestration and other host modules drive chats through `AgentChatRuntime` (`runtime_handle.rs`), a cloneable async handle owned by the host. It goes through the same session actors, receipts and events as the wire verbs; it never touches provider processes directly and never blocks the host actor.

```rust
impl AgentChatRuntime {
    async fn create(&self, input: CreateChatInput, ctx: CallerCtx) -> HostResult<Value>; // {chatId, tabId, snapshot}
    async fn list(&self, workspace_id: Option<&str>, include_archived: bool) -> HostResult<Vec<Value>>;
    async fn command(&self, chat_id: &str, op: ChatOp, ctx: CallerCtx, receipt: Option<ReceiptKey>) -> HostResult<Value>;
    async fn send(&self, chat_id: &str, input: SendInput, ctx: CallerCtx) -> HostResult<Value>;
    async fn snapshot(&self, chat_id: &str) -> HostResult<Value>;
    fn subscribe(&self) -> tokio::sync::broadcast::Receiver<ChatRuntimeEvent>;
    fn register_launch_hook(&self, hook: Arc<dyn ProviderLaunchHook>);
}

enum ChatRuntimeEvent {
    Changed { chat_id, workspace_id, cursor, delta: Value },
    ChatsChanged { workspace_id: Option<String> },
}
```

- `CreateChatInput {workspace_id, provider, provider_instance_id?, model?, runtime_mode?, interaction_mode?, title?, metadata?}`. `metadata` is host-only JSON stored on the chat (for example the orchestration run that created it). Clients cannot set it and never receive it; snapshots carry only `lineage`, projected from the explicit string keys `originKind`, `parentChatId`, `runId`, `taskId` and `createdByChatId`.
- `CallerCtx {scope, actor, mobile}` is what receipts and actor stamps use; host code passes its own identity (for example `agent:<chatId>` or `runtime`).
- A lagged `subscribe` receiver must reload `snapshot`, exactly like a client that sees a cursor gap.
- `ProviderLaunchHook::prepare(&self, launch: &mut ProviderLaunch)` runs before every provider spawn, resumes included. `ProviderLaunch` carries `chat_id`, `provider`, `provider_instance_id`, `cwd`, `model`, `runtime_mode`, the instance config, and `mcp_servers: Vec<McpServerSpec>` / `env: BTreeMap<String, String>` that a hook may fill. The servers go to `SessionStartInput.mcp_servers`; when the started provider's `capabilities().mcp_injection` cannot carry one of them, startup fails with an error naming the server rather than dropping it.
- `SendInput.origin` is host-only (`{kind: chatMessage|orchestrationWake|subagentWake, senderChatId?, taskIds?}`); the wire verbs always send `{kind: user}`.

## Persistence

Chats persist through the `RuntimeStore` agent chat API in `alera-core` (`agent_chat_*`). Every session commit sends the full snapshot header and a delta computed by diffing it against the last committed header, plus the item rows and text appends it touched and at most one receipt; the store verifies the delta explains the header and moves the cursor by one. Native ids are mapped per generation under kinds suffixed with the provider process (`item@<epoch>`), because JSON-RPC and local ids restart with every process. Startup recovery is committed by the host through the same path so the recovery notice keeps the wire shape above.

## Attachment Uploads And Remote Setup

`agentChatAttachmentUploadV1` exposes human-only uploads on desktop and paired mobile. Every upload verb carries `{workspaceId, chatId, uploadId}`; the connection supplies caller authority. The hub routes remote workspace uploads to their owner and requires that owner's capability. Bound agent credentials cannot upload or consume a human receipt.

| Verb | Additional payload | Result |
| --- | --- | --- |
| `agentChat.attachment.start` | `{type: file\|localImage, name, sizeBytes, sourceDigest?}` | `{uploadId, chunkBytes, offset, complete, maxFileBytes}` |
| `agentChat.attachment.chunk` | `{offset, dataBase64}` | `{nextOffset}` |
| `agentChat.attachment.complete` | None | `{attachmentId, path, type, name, sizeBytes}` |
| `agentChat.attachment.cancel` | None | `{}` |

Reservations permit exact chunk replay and resume from the returned offset. Immutable source digests reject changed file content; clients retain the completed receipt with the original pending message ID. Send resolves `attachmentId` on the owner, checks caller/workspace/chat scope and bounds a message to 32 attachments. Files are limited to 32 MiB, chunks to 256 KiB, and storage to 128 MiB with 512 reservations. Unused uploads expire after 24 hours and are swept on the next reservation. Files consumed for a native send survive ambiguous delivery and remain until their chat is deleted.

Remote Sign In, Install and Update require `agentChatRemoteProviderSetupV1` on both hub and owner. Only an authenticated, unbound desktop App can open setup using opaque `{providerInstanceId, action}` metadata. The owner validates its verified recipe and hydrates its own profile environment and secrets. Each desktop holds a private lease; input, output, reconnection and cleanup honor that lease. Dialog close revokes it, and the owner terminates the ephemeral setup session after the final lease is removed. Paired phones retain copy-only setup and do not receive this capability.

## Host wiring ownership

The base chat backend owns these shared host edits; other work should add to them through the named seams instead of editing them in parallel:

- `server.rs`: module declarations, the `agent_chats: AgentChatHost` field on `ServerActor`, the `agent_chat_tabs` flag on `ClientState`, and the `ServerCommand::AgentChat` arm.
- `server_command.rs` (`AgentChat(AgentChatCommand)` variant) and `server_command_inbox_budget.rs` (completion lane and byte size for it).
- `server_runner.rs` (runtime construction and restart recovery), `server_shutdown.rs` (graceful provider close), `lifecycle.rs` (busy chats block idle shutdown; live providers count like detached terminals).
- `client_delivery.rs` and `mobile_hello_requests.rs` (`supportedTabKinds`), `mobile_gateway_surface.rs` (`agentChat.*` allowlist, `agentChatV1`), `protocol_capabilities.rs`, `control_file.rs`, `host_status.rs`.
- `deferred_requests.rs` (one call into `try_start_agent_chat_request`), `tab_compatibility.rs`, `requests.rs` (`tab.upsert` guard), `deferred_workspace_lifecycle.rs` (`tab.remove` guard), `session_termination.rs` (tab and workspace effects).
- Remote: `host_link_routing.rs` forwarding, `hub_reverse_policy.rs` denial, and the satellite event relay.
- New host files: `agent_chat_host.rs`, `agent_chat_requests.rs`, `agent_chat_tabs.rs`, `agent_chat_remote.rs`, and everything under `agent_chat_runtime/`.

In-process seam for orchestration: `ServerActor::agent_chat_runtime() -> Option<AgentChatRuntime>` (a cloneable handle; `None` only in actors built without a runtime). Re-exported from `server::agent_chat_runtime`: `AgentChatRuntime`, `CreateChatInput`, `ChatOp`, `SendInput` (with host-only `origin`), `CallerCtx`, `ChatRuntimeEvent`, `ProviderLaunchHook`, `ProviderLaunch`. Orchestration verbs and their dispatch belong in their own modules; a single call site in `deferred_requests.rs` next to the chat one is the expected wiring.
