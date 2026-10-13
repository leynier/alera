# agent chat runtime

Runtime-host chat sessions over the Rust provider adapters (`alera-provider-*`). The host owns every provider process and persists the transcript, so a chat survives the app closing and is driven identically from desktop and paired phones. Chats coexist with terminal tabs.

## Capability and tab kind

- `agentChatV1` is advertised in the control file, `status.get` and `MOBILE_HELLO_CAPABILITIES`. It is additive and does not bump `aleraTerminalHostProtocolVersion` or the mobile protocol version.
- A client opts in by sending `supportedTabKinds: ["agentChat"]` in `hello` (local) or `mobile.hello`. Clients that do not declare it never see `agentChat` tabs in `tab.list`, `tab.find` or tab events, cannot `tab.upsert` over one and cannot `tab.remove` one, and never receive `agentChat*` events.
- Tab record: `kind: "agentChat"`, `payload: {chatId, provider, providerInstanceId, model?}`, `title` = chat title. The payload keys are host-owned: a client `tab.upsert` keeps the stored values.
- `tab.remove` of an `agentChat` tab archives the chat exactly like `agentChat.close` (provider stopped, queued input cancelled, history kept). Nothing is deleted.

## Verbs

Every mutation carries a client `requestId` (string, unique per caller). The receipt key is `(callerScope, verb, requestId)`; `callerScope` and the actor come from the connection (`desktop`, `cli`, `mobile:<deviceId>`), never from the payload. A replay with the same payload digest returns the stored response; a different payload returns `errorCode: "request_conflict"`. Chat-scoped verbs SHOULD also carry `workspaceId` (routing for remote workspaces).

| Verb | Payload | Result |
| --- | --- | --- |
| `agentChat.providers` | `{workspaceId?, refreshModels?}` | `{providers: [Provider]}` |
| `agentChat.list` | `{workspaceId?, includeArchived?}` | `{chats: [ChatSummary]}` |
| `agentChat.create` | `{requestId, workspaceId, provider, providerInstanceId?, model?, runtimeMode?, interactionMode?, title?}` | `{chatId, tabId, snapshot}` |
| `agentChat.reopen` | `{requestId, chatId}` | `{chatId, tabId, snapshot}` (archived chat gets a new tab) |
| `agentChat.snapshot` | `{chatId}` | `Snapshot` (items bounded to 256 KiB) |
| `agentChat.history` | `{chatId, before, limit?}` | `{items, turns, historyBefore?}` (bounded to 256 KiB) |
| `agentChat.payload` | `{chatId, workspaceId?, itemId, index?:0, limit?:200}` | `{chunks:[{index,text}], nextIndex?, segmentCount, format:"json", revision}` (bounded to 256 KiB) |
| `agentChat.send` | `{requestId, chatId, clientMessageId, text, attachments?, delivery?: auto\|steer\|queue, model?, interactionMode?}` | `{delivery: started\|queued\|steered, itemId?, turnId?, queueId?}` |
| `agentChat.queueCancel` | `{requestId, chatId, queueId}` | `{cancelled: bool}` |
| `agentChat.interrupt` | `{requestId, chatId, turnId?}` | `{acknowledged: true}` (the turn ends through events) |
| `agentChat.respond` | `{requestId, chatId, runtimeRequestId, response}` | `{resolved: true}` |
| `agentChat.configure` | `{requestId, chatId, provider?, providerInstanceId?, model?, runtimeMode?, interactionMode?}` | `{snapshot}` |
| `agentChat.rename` | `{requestId, chatId, title}` | `{title}` |
| `agentChat.recover` | `{requestId, chatId, mode?: resume\|restart}` | `{snapshot}` |
| `agentChat.close` | `{requestId, chatId}` | `{archived: true}` |

`send` with `delivery: auto` starts a turn when idle and queues behind a running turn; `steer` is accepted only when the session capability `steer` is true (`errorCode: "unsupported"` otherwise). `clientMessageId` is idempotent on its own: resending it returns the original result.

`respond.response` is one of `{type: "approval", decision}`, `{type: "userInput", answers: {questionId: value}}`, `{type: "elicitation", action, content?}`, `{type: "native", result}`. `runtimeRequestId` is the runtime's id; the provider's native id never leaves the host. The first writer wins: a later answer gets `request_resolved`. A decision outside the request's `decisions` gets `unsupported`.

`configure` changing `provider`/`providerInstanceId` is accepted only while idle with no open requests and no queued or background work (`errorCode: "turnActive"` otherwise). It keeps every earlier turn and item (each carries its generation's provider), closes the old process and starts a new native session. The first user turn sent to the new provider is prefixed with a bounded quoted transcript of prior user and assistant text (no reasoning, no tool payloads). No model is called until that send. `model`, `runtimeMode` and `interactionMode` changes apply through the adapter's native control when it has one, otherwise by recreating the idle session with the same handoff; a change the provider cannot honor returns `unsupported`.

Error codes (`errorCode` next to `error`): `request_conflict`, `request_resolved`, `unsupported`, `turnActive`, `turnNotActive`, `chatNotFound`, `chatArchived`, `providerUnavailable`.

## Events

- `agentChatChanged {chatId, workspaceId, cursor, delta}`. Every persisted change increments `cursor` by exactly one and is committed before it is broadcast. A client that sees `cursor > known + 1`, or reconnects, reloads `agentChat.snapshot`. Changes with `cursor <= known` are stale and ignored.
- `agentChatsChanged {workspaceId?}`: the chat list changed (create, close, reopen, rename, provider switch).
- `workspaceTabsChanged` as for any tab create, remove or rename.

Streamed text is coalesced for 50 to 100 ms or 8 KiB per chat and flushed on item completion, turn end and before any snapshot.

Large redacted native data is retained in hidden payload rows rather than discarded. Normal snapshots, history and public deltas omit those rows while every durable commit retains them and every public change keeps its cursor. `agentChat.payload` takes the visible head item ID and uses zero-based chunk indices. It is an explicit human read, including archived chats; credential-bound agents retain their orchestration-only allowlist. The optional Dart payload repository verifies contiguous chunks and a stable revision. A changed or incomplete payload returns an error so the person can retry instead of combining data from different versions.

## Shapes

`Snapshot {chatId, workspaceId, tabId, providerInstanceId, provider, title, archived, cursor, session, turns[], items[], pendingRequests[], queue[], usage?, recovery?, lineage?, historyBefore?}`

`session {status: starting|ready|running|waiting|stopped|error, model?, runtimeMode, interactionMode, activeTurnId?, cwd?, generation, capabilities {resume, interrupt, approvals, userInput, mcpElicitation, streaming, modelSwitch, steer, fork, rollback, attachments, images, plan}, errorMessage?}`. `runtimeMode`: `approval-required|auto-accept-edits|auto|full-access`; `interactionMode`: `default|plan`.

`turn {turnId, status: running|completed|failed|interrupted|cancelled, startedAt, completedAt?, errorMessage?, reason?, model?, provider, providerInstanceId, generation}`. A turn cut short by a host restart is `interrupted` with `reason: "runtimeRestarted"`.

`item {itemId, turnId?, type, status: inProgress|completed|failed|declined, streaming, createdAt, updatedAt, title?, detail?, text?, reasoningText?, output?, clientMessageId?, attachments?, actor?, normalized {command?, cwd?, exitCode?, durationMs?, changes?, toolName?, server?, input?, result?, query?, url?, imagePath?, planSteps?, explanation?, origin?}, data?}`. A `user_message` always has `normalized.origin {kind: user|chatMessage|orchestrationWake, senderChatId?, taskIds?}`; only host code sets a kind other than `user`. `type` is snake_case: `user_message, assistant_message, reasoning, plan, command_execution, file_change, mcp_tool_call, dynamic_tool_call, collab_agent_tool_call, web_search, image_view, review_entered, review_exited, context_compaction, error, notice, unknown`.

`request {requestId, kind, turnId?, itemId?, createdAt, title?, detail?, command?, cwd?, path?, questions[], decisions[], elicitation? {mode, message, schema, url?}, expiresAt?}`. `kind` is snake_case (`command_execution_approval`, `file_change_approval`, `tool_user_input`, `mcp_elicitation_approval`, ...). `decisions` lists exactly what the provider accepts (`accept, acceptForSession, acceptAlways, decline, cancel`).

`delta {items?, removedItemIds?, textAppends? [{itemId, stream: text|reasoningText|output, offset, text}], turns?, requests? (the full pending list), queue? (the full queue), session?, usage?, title?, provider?, providerInstanceId?, archived?, recovery? (null clears)}`. `offset` counts UTF-16 code units of the field before the append.

`queue entry {queueId, clientMessageId, text, attachments?, createdAt}`.

`usage {tokens {input?, output?, cached?, reasoning?, context?, contextWindow?}, windows[]}`.

`recovery {kind: providerExited|resumable|notResumable|providerMissing|authRequired, message, canResume, canRestart}`.

`Provider {provider, providerInstanceId, label, available, unavailableReason?, custom, models [{id, label, isDefault}], modelsSource: discovered|configured|providerDefault, capabilities, runtimeModes[], interactionModes[]}`. When no cheap model discovery exists the list holds the configured model or a single `providerDefault` entry; nothing is invented.

`ChatSummary {chatId, workspaceId, tabId?, title, provider, providerInstanceId, model?, status, archived, cursor, updatedAt}`.

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
- `SendInput.origin` is host-only (`{kind: chatMessage|orchestrationWake, senderChatId?, taskIds?}`); the wire verbs always send `{kind: user}`.

## Persistence

Chats persist through the `RuntimeStore` agent chat API in `alera-core` (`agent_chat_*`). Every session commit sends the full snapshot header and a delta computed by diffing it against the last committed header, plus the item rows and text appends it touched and at most one receipt; the store verifies the delta explains the header and moves the cursor by one. Native ids are mapped per generation under kinds suffixed with the provider process (`item@<epoch>`), because JSON-RPC and local ids restart with every process. Startup recovery is committed by the host through the same path so the recovery notice keeps the wire shape above.

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
