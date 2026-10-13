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
- The injected MCP server is `alera mcp serve --runtime-dir <dir> --chat-credential-file <path>` with server name `alera`. No secret is ever on argv or in snapshots.
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

Receipt-backed mutations (`delegate`, `send`, `cancel`, `interrupt`, `respond` and `configure`) carry `requestId`. Receipts are keyed by `(scope, verb, requestId)` plus a canonical payload digest: the same payload replays the stored response, a different one fails with `request_conflict`. Task acknowledgement is a separate idempotent state update without a request id; bound callers may acknowledge only tasks in their descendant lineage.

| Verb | Payload | Result |
| --- | --- | --- |
| `chatOrchestration.capabilities` | `{}` | `{maxWaitSeconds: 50, providers: [Provider + {mcpInjection {stdio, http}, orchestration {supported, reason?}}], runtimeModes, ceilingRuntimeModes, caller?: {chatId, runtimeMode}}` |
| `chatOrchestration.delegate` | `{requestId, task, title?, role?, notify?, mode?: async\|wait, waitSeconds?, agent?: {providerInstanceId, model?, options?}, runtimeMode?, interactionMode?, target}` | `{taskId, chatId?, workspaceId?, status, result?, task}` |
| `chatOrchestration.send` | `{requestId, chatId, message, delivery?: auto\|queue, expectReply?}` | `{chatId, delivery, taskId?}` |
| `chatOrchestration.task` | `{taskId, acknowledge?}` | `{task}` |
| `chatOrchestration.tasks.list` | `{parentChatId?, childChatId?, rootTaskId?, workspaceId?, projectId?, statuses?, attention?, limit?, cursor?}` | `{tasks, nextCursor?}` |
| `chatOrchestration.wait` | `{taskIds, waitSeconds?, until?: all\|any}` (default `all`) | `{tasks, timedOut}` |
| `chatOrchestration.cancel` | `{requestId, taskId, reason?}` | `{task, cancelledTaskIds}` |
| `chatOrchestration.interrupt` | `{requestId, chatId}` | `{acknowledged: true}` |
| `chatOrchestration.requests` | `{taskId?, chatId?}` | `{requests: [{chatId, taskId?, request}]}` |
| `chatOrchestration.respond` | `{requestId, chatId, runtimeRequestId, response}` | `{resolved: true}` |
| `chatOrchestration.configure` | `{requestId, chatId, providerInstanceId?, model?, runtimeMode?, interactionMode?}` | `{snapshot}` (as `agentChat.configure`) |
| `chatOrchestration.read` | `{chatId, limit?}` | `{chat, messages, plans, truncated}` |
| `chatOrchestration.list` | `{workspaceId?, projectId?, hostId?, includeArchived?}` | `{chats}` |

`target` is exactly one of `{chat: {chatId}}`, `{workspace: {workspaceId}}` or `{newWorkspace: {projectId, hostId, mode: worktree|shared, branch?, sourceBranch?, reuseExistingBranch?, name?, parentWorkspaceId?, setup?: inline|deferred}}`. `hostId` is `local` or an SSH target id and is never implied. New workspaces are created through `workspace.createManaged` (worktree) or `workspace.createShared` (shared) on the host's own client, so setup, barriers, remote routing and broadcasts are the ordinary ones. Nothing selects a workspace or tab.

`mode: wait` returns once the task leaves `preparing|running`, or after `waitSeconds` (default and maximum 50). `wait` is bounded the same way; call it again to keep waiting.

`notify`: `always` (async default), `settled_only` (wait default; becomes `always` when the wait times out), `never`.

Nonempty `agent.options` is currently unsupported. Delegating to an existing chat does not implicitly replace its provider or runtime policy: incompatible explicit settings fail, and the caller can configure an eligible idle chat first. A differing model is accepted only when the target can honor it for that turn.

### Task

The store record is internal; the wire task is a projection:

`{taskId, kind: delegate|message, status, parentTaskId?, rootTaskId, depth, parentChatId?, childChatId?, workspaceId?, projectId?, hostId?, target, title?, role?, brief?, notify, attention: bool, attentionKind?: needs_input|failed, resultDelivery: pending|notified|acknowledged, result?: {text, truncated, turnId?}, error?: {code?, message}, pendingRequestCount?, provider?, providerInstanceId?, model?, runtimeMode?, labels?: {parentChatTitle?, childChatTitle?, projectName?, workspaceName?, hostLabel?}, actor, createdAt, updatedAt, completedAt?}`

`status`: `preparing|running|needs_input|completed|failed|interrupted|cancel_requested|cancelled`. A task completes when the child's turn started for it (matched by `clientMessageId`) settles; its result is the final assistant text of that turn (bounded). An open child request moves it to `needs_input`; answering moves it back to `running`. `brief` is the task text, bounded like the result. `attention` is true for `needs_input`, and for `failed` until the result is acknowledged. `task` with `acknowledge: true` acknowledges a settled result; reading without it never does, so a person looking at a child's task does not take the result from its parent.

### Chat summary and read

`chat` is the agent chat summary plus `projectId`, `hostId`, `runtimeMode` and `lineage {parentChatId?, taskId?, role?}`. `read.messages` are `{itemId, role: user|assistant, text, createdAt, origin?}` with `origin {kind: user|chatMessage|orchestrationWake, senderChatId?, taskIds?}`; `read.plans` are `{itemId, explanation?, steps: [{step, status}]}`. No reasoning, tool payloads or raw provider data.

## Events

`chatOrchestrationChanged {taskId, parentChatId?, childChatId?, workspaceId?}` to every authenticated local and mobile client after the change is committed. Clients reload the task or list.

## Parent wakes

A wake is a message into the parent chat with `origin {kind: orchestrationWake, taskIds}` and the cohort's stable `clientMessageId` (`chat-orchestration-wake:<parentChatId>:<generation>`). It names the tasks; results are read with `task`. Completions join the parent's open cohort; the cohort is sealed and sent only while the parent has no running turn, so completions during a turn merge into one wake and a wake never interrupts or steers. A result acknowledged before delivery is withdrawn from the cohort. A sealed cohort is resent after a restart; the stable id makes that idempotent.

## Errors

`errorCode` (snake_case) next to `error`: `request_conflict`, `chat_not_found`, `task_not_found`, `not_in_lineage`, `mode_ceiling`, `caller_turn_inactive`, `chat_credential_invalid`, `chat_scope_denied`, `chat_archived`, `invalid_target`, `unsupported`, `host_unavailable`.

## Remote hosts

The hub owns the ledger and task routing. A satellite owns its chats' providers and transcripts. A chat on a satellite gets its credential from the satellite, which forwards `chatOrchestration.*` from that bound connection to the hub with `originChatId`; the hub accepts it only when that chat's workspace belongs to the forwarding host.
