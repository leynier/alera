# chat orchestration host service

Delegation, messages and task tracking between agent chats, on top of `AgentChatRuntime`. It is separate from terminal orchestration: its own verbs (`chatOrchestration.*`), tables (`chatOrchestration*`), event and identity. The product contract is `docs/agent-chat-orchestration.md`; this file is the wire and in-process contract.

## Capability

`chatOrchestrationV1` is advertised in the control file, `status.get` and `MOBILE_HELLO_CAPABILITIES`. It is additive and does not bump `aleraTerminalHostProtocolVersion` or the mobile protocol version.

## Caller identity

| Connection | Scope | Actor | Authority |
| --- | --- | --- | --- |
| Desktop app | `desktop` | `desktop` | Human: every verb, every chat |
| Local CLI without a credential | `cli` | `cli` | Human: every verb, every chat |
| Paired phone | `mobile:<deviceId>` | `mobile:<deviceId>` | Human: same verbs as desktop |
| Chat-bound agent | `chat:<chatId>` | `agent:<chatId>` | Bound agent rules below |

The scope and actor always come from the connection; payload fields such as `actor`, `from` or `scope` are ignored.

### Chat credential

- The host mints one credential per chat generation in a `ProviderLaunchHook` before every provider spawn: an opaque random secret (64 hex characters), written to `<runtimeDir>/agent-chat-mcp/<credentialId>.token` (directory `0700`, file `0600`, owner only). Only the SHA-256 (hex) is persisted. The previous credential of that chat is revoked and its file removed on every new spawn, provider switch, close and archive.
- The injected MCP server is `alera mcp --runtime-dir <dir> serve --chat-credential-file <path>` with server name `alera`. No secret is ever on argv or in snapshots.
- The CLI reads the file (trimmed) and sends it in `hello` as `chatCredential: "<token>"`, next to the usual `token` and `protocolVersion`. A missing or unreadable file is a CLI error; the CLI never falls back to an unbound connection.
- The host verifies the hash against an unrevoked credential. A mismatch, a revoked credential, or a chat that is archived fails `hello` with `errorCode: "chat_credential_invalid"`. Success adds `chatBinding: {chatId}` to the hello response and binds the connection for its lifetime.
- Bound connections may only call `chatOrchestration.*`, `project.list`, `workspace.list` and `status.get`; anything else is refused with `errorCode: "chat_scope_denied"`.

### Bound agent rules

- Every call needs the caller chat to be unarchived with a running turn (`errorCode: "caller_turn_inactive"`), and the binding's generation must still be current (`chat_credential_invalid`).
- Reads (`list`, `read`, `task`, `tasks.list`, `wait`, `capabilities`, `requests`) and `send` / `delegate` work across every project, workspace and host this runtime knows.
- `interrupt`, `respond`, `configure` and `cancel` work only on the caller's descendants (`errorCode: "not_in_lineage"`). Humans are not limited by lineage.
- A target chat or a new child may not run in a runtime mode above the caller's (`errorCode: "mode_ceiling"`); order: `approval-required < auto-accept-edits < auto < full-access`. A child without `runtimeMode` inherits the caller's.
- `read` returns only user and assistant text and plans, for every caller.

## Verbs

Receipt-backed mutations (`delegate`, `send`, `cancel`, `interrupt`, `respond`, `configure`, and `task` with `acknowledge: true`) carry `requestId`. Receipts are keyed by `(scope, verb, requestId)` plus a canonical payload digest: the same payload replays the stored response, a different one fails with `request_conflict`. A task acknowledgement's digest contains its task id and acknowledgement action, and its bound lineage is checked before replay. New CLI and MCP acknowledgement mutations must send a request id. Legacy `task {acknowledge: true}` without `requestId` remains supported as an idempotent state update, but does not store a receipt or guarantee stable response replay or request-id conflicts. Plain task queries never acknowledge a result or record a receipt.

| Verb | Payload | Result |
| --- | --- | --- |
| `chatOrchestration.capabilities` | `{}` | `{maxWaitSeconds: 50, providers: [Provider + {mcpInjection {stdio, http}, orchestration {supported, reason?}}], runtimeModes, ceilingRuntimeModes, caller?: {chatId, runtimeMode}}` |
| `chatOrchestration.delegate` | `{requestId, task, parentChatId?, title?, role?, notify?, mode?: async\|wait, waitSeconds?, agent?: {providerInstanceId, model?, options?}, runtimeMode?, interactionMode?, target}` | `{taskId, chatId?, workspaceId?, status, result?, task}` |
| `chatOrchestration.send` | `{requestId, chatId, message, parentChatId?, delivery?: auto\|queue, expectReply?}` | `{chatId, delivery, taskId?}` |
| `chatOrchestration.task` | `{taskId, acknowledge?, requestId?}` (new acknowledgements send `requestId`) | `{task}` |
| `chatOrchestration.tasks.list` | `{parentChatId?, childChatId?, rootTaskId?, workspaceId?, projectId?, statuses?, attention?, limit?, cursor?}` | `{tasks, nextCursor?}` |
| `chatOrchestration.wait` | `{taskIds, waitSeconds?, until?: all\|any}` (default `all`) | `{tasks, timedOut}` |
| `chatOrchestration.cancel` | `{requestId, taskId, reason?}` | `{task, cancelledTaskIds}` |
| `chatOrchestration.interrupt` | `{requestId, chatId}` | `{acknowledged: true}` |
| `chatOrchestration.requests` | `{taskId?, chatId?}` | `{requests: [{chatId, taskId?, request}]}` |
| `chatOrchestration.respond` | `{requestId, chatId, runtimeRequestId, response}` | `{resolved: true}` |
| `chatOrchestration.configure` | `{requestId, chatId, providerInstanceId?, model?, reasoningEffort?, runtimeMode?, interactionMode?}` | `{snapshot}` (as `agentChat.configure`) |
| `chatOrchestration.read` | `{chatId, limit?}` | `{chat, messages, plans, truncated}` |
| `chatOrchestration.list` | `{workspaceId?, projectId?, hostId?, includeArchived?}` | `{chats}` |

`target` is exactly one of `{chat: {chatId}}`, `{workspace: {workspaceId}}` or `{newWorkspace: {projectId, hostId, mode: worktree|shared, branch?, sourceBranch?, reuseExistingBranch?, name?, parentWorkspaceId?, setup?: inline|deferred}}`. `hostId` is `local` or an SSH target id and is never implied. New workspaces are created through `workspace.createManaged` (worktree) or `workspace.createShared` (shared) on the host's own client, so setup, barriers, remote routing and broadcasts are the ordinary ones. Nothing selects a workspace or tab.

`mode: wait` returns once the task leaves `preparing|running`, or after `waitSeconds` (default and maximum 50). `wait` is bounded the same way; call it again to keep waiting.

`notify`: `always` (async default), `settled_only` (wait default; becomes `always` when the wait times out), `never`.

With `chatOrchestrationPersonParentV1`, authenticated desktop, local CLI, and paired-phone callers may set `parentChatId` to an existing unarchived local or remote chat. The task belongs to that parent's dock, active task lineage, and wake delivery while its actor remains the person and its brief has no `senderChatId`. Omitting the parent keeps standalone tasks. A bound agent's parent always remains its authenticated chat; a conflicting payload fails with `not_in_lineage`. Satellite reverse callers cannot claim person parent authority. `send` ignores a person's parent when `expectReply` is false. Caller and lineage authorization precede receipt lookup. A matching receipt replays its stored response during a native freeze; a changed digest still fails with `request_conflict`. Only new requests apply the `nativeOperationPending` or `nativeOperationUncertain` parent/destination check before workspace preparation or native input. The store also checks the parent, resolved root, child, and existing-chat destination atomically at task creation, so a freeze observed during atomic task admission prevents the task and subsequent workspace effects.

With `chatOrchestrationEffortV1`, `agent.options` accepts only `reasoningEffort` as a nonempty string; omit it for the default. Unknown keys and non-string efforts are rejected. The destination runtime validates the selected model's verified effort support before creation or message admission, including on a remote host. Delegating to an existing chat does not implicitly replace its provider or runtime policy: incompatible explicit settings fail, and the caller can configure an eligible idle chat first. A differing model is accepted only when the target can honor it for that turn.

For `configure`, omitting `model` or `reasoningEffort` preserves the current selection; explicit `null` resets it to the instance/provider model default or default effort. This distinction is preserved through remote operations and receipt digests. Model or instance changes can clear an incompatible effort according to the chat runtime's configuration rules. Runtime ceilings remain derived from the authenticated caller.

### Task

The store record is internal; the wire task is a projection:

`{taskId, kind: delegate|message, status, parentTaskId?, rootTaskId, depth, parentChatId?, childChatId?, workspaceId?, projectId?, hostId?, target, title?, role?, brief?, notify, attention: bool, attentionKind?: needs_input|failed, resultDelivery: pending|notified|acknowledged, result?: {text, truncated, turnId?}, error?: {code?, message}, pendingRequestCount?, provider?, providerInstanceId?, model?, runtimeMode?, labels?: {parentChatTitle?, childChatTitle?, projectName?, workspaceName?, hostLabel?}, actor, createdAt, updatedAt, completedAt?}`

`status`: `preparing|running|needs_input|completed|failed|interrupted|cancel_requested|cancelled`. A task completes when the child's turn started for it (matched by `clientMessageId`) settles; its result is the final assistant text of that turn (bounded). An open child request moves it to `needs_input`; answering moves it back to `running`. `brief` is the task text, bounded like the result. `attention` is true for `needs_input`, and for `failed` until the result is acknowledged. `task` with `acknowledge: true` acknowledges a settled result without changing its status; an unsettled task fails with `task_not_settled` and does not consume the request id. Reading without acknowledgement never writes a receipt or takes the result from its parent.

### Chat summary and read

`chat` is the agent chat summary plus `projectId`, `hostId`, `runtimeMode` and `lineage {parentChatId?, taskId?, role?}`. `read.messages` are `{itemId, role: user|assistant, text, createdAt, origin?}` with `origin {kind: user|chatMessage|orchestrationWake, senderChatId?, taskIds?}`; `read.plans` are `{itemId, explanation?, steps: [{step, status}]}`. No reasoning, tool payloads or raw provider data.

## Events

`chatOrchestrationChanged {taskId, parentChatId?, childChatId?, workspaceId?}` to every authenticated local and mobile client after the change is committed. Clients reload the task or list.

## Parent wakes

A wake is a message into the parent chat with `origin {kind: orchestrationWake, taskIds}` and the cohort's stable `clientMessageId` (`chat-orchestration-wake:<parentChatId>:<generation>`). It names the tasks; results are read with `task`. Completions join the parent's open cohort; the cohort is sealed and sent only while the parent has no running turn, so completions during a turn merge into one wake and a wake never interrupts or steers. A result acknowledged before delivery is withdrawn from the cohort. A sealed cohort is resent after a restart; the stable id makes that idempotent.

## Errors

`errorCode` (snake_case) next to `error`: `request_conflict`, `chat_not_found`, `task_not_found`, `not_in_lineage`, `mode_ceiling`, `caller_turn_inactive`, `chat_credential_invalid`, `chat_scope_denied`, `chat_archived`, `invalid_target`, `unsupported`, `host_unavailable`, `chat_orchestration_shutdown`.

## Host shutdown

The host calls `ChatOrchestrationService::shutdown().await` before `AgentChatRuntime::shutdown`. Orchestration permanently closes admission, aborts its requests and task monitors, and awaits their cancellation within one five-second deadline. Wake delivery is inline in those jobs and quiesces with them. A `false` result retains unfinished handles for a shutdown retry; the host must leave chat actors running and must not claim disposal until shutdown returns `true`. Completed jobs remove their own handles instead of accumulating task history in memory.

Shutdown does not fail or cancel durable tasks, remove receipts, or acknowledge undelivered wakes. A request stopped during preparation or inference leaves its committed state for startup recovery. A sealed wake keeps its stable message id for replay. Requests arriving after admission closes fail with `chat_orchestration_shutdown` before authorization, target preparation, or runtime effects; ordinary request authorization and receipt behavior remain unchanged while admission is open.

## Remote hosts

The hub owns the ledger and task routing. A satellite owns its chats' providers and transcripts. A chat on a satellite gets its credential from the satellite, which forwards `chatOrchestration.*` from that bound connection to the hub with `originChatId`; the hub accepts it only when that chat's workspace belongs to the forwarding host.
