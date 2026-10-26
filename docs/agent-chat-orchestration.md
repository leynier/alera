# Chat orchestration

## Scope

The runtime owns orchestration between agent chats, including chats in different projects and on connected hosts. This system is separate from terminal orchestration. It uses the same chat actors, persistence, provider sessions, approvals and synchronization as `agentChat.*`. Desktop and paired mobile expose the same human controls. Neither delegation nor messages change the user's selected workspace or tab.

Delegation always names its target: an existing chat, a new chat in an existing workspace, or a new workspace with `mode: worktree|shared`. New workspaces name their project and host explicitly and go through the existing managed/shared workspace API. A child receives the supplied brief only, without copying its parent's history. Provider switches keep chat identity and lineage while changing native session generation.

## Contract

The additive capability is `chatOrchestrationV1`. Host verbs use `chatOrchestration.*`; MCP tools use the `chat_` prefix so they cannot collide with terminal tools. The verbs are `capabilities`, `delegate`, `send`, `task`, `tasks.list`, `wait`, `cancel`, `interrupt`, `backgroundWait`, `requests`, `respond`, `configure`, `read` and `list`. The CLI group is `alera chat`. Receipt-backed mutations (`delegate`, `send`, `cancel`, `interrupt`, `respond` and `configure`) carry `requestId`; MCP exposes `clientRequestId` and maps it to that field. A task acknowledgement with an explicit request ID also uses a durable receipt; legacy no-ID acknowledgement remains compatible. Pure task reads never acknowledge.

`delegate` accepts `{task, title?, role?, notify?, mode: async|wait, waitSeconds?, requestId, agent?: {providerInstanceId?, model?, options?}, runtimeMode?, interactionMode?, target}`. A target is exactly one of `{chat:{chatId}}`, `{workspace:{workspaceId}}` or `{newWorkspace:{projectId,hostId,mode:worktree|shared,branch?,sourceBranch?,reuseExistingBranch?,name?,parentWorkspaceId?,setup:inline|deferred}}`. Worktree targets require `branch`; setup defaults to `inline`. Its response includes `{taskId,chatId?,workspaceId?,status,result?}`.

`send` accepts `{chatId,message,delivery:auto|queue,expectReply,requestId}`. With `expectReply`, it creates a message task whose completion can notify the sender. `task` reads and optionally acknowledges a result; `wait` waits for at most 50 seconds. `tasks.list` includes lineage, target, status, attention and result delivery state. A bound agent that names no `parentChatId`, `childChatId` or `rootTaskId` lists only its own chat's delegations, because several chats in one workspace each own theirs; naming another lineage still reads it, marked `readOnly`. `read` exposes user and assistant text and canonical plans, without provider credentials or hidden reasoning. The event `chatOrchestrationChanged {taskId,parentChatId?,childChatId?,workspaceId?}` invalidates lists on desktop and mobile.

`configure` preserves omitted model and reasoning effort. Explicit null resets either to its provider default. CLI `--reset-model` and `--reset-reasoning-effort` and bound MCP `resetModel:true` and `resetReasoningEffort:true` express these resets without an empty identifier. Settings administration and direct lifecycle/history operations use the separate [Agent Chat CLI And MCP](agent-chat-cli.md) surface and remain absent from injected chat credentials.

Tasks have app-owned `taskId` distinct from `childChatId`, and states `preparing|running|needs_input|completed|failed|interrupted|cancel_requested|cancelled`. Completion follows the child's settled turn, not request acknowledgement. Results contain bounded final assistant text. Open child requests produce `needs_input`. Follow-up work produces a new task even when reusing a child chat.

Human delegate/send requests can explicitly name `parentChatId` (`alera chat --parent-chat-id` on those actions), binding task and wake delivery to their originating chat. This field does not impersonate a bound agent or replace host-derived caller identity. Bound callers retain their credentialed parent and lineage restrictions; their injected MCP surface does not offer human parent selection.

## Human CLI And Public MCP

`alera chat --json human <operation>` accepts an exact structured body through `--payload`, `--payload-file`, or `--payload-stdin`. It refuses chat-bound credentials before dispatch, rather than replacing them. Public MCP tools call this human route and remain absent from the injected catalog. Caller identity comes from the existing host handshake and MCP origin, not a fabricated agent token.

| Public tool | Access | Explicit operations |
| --- | --- | --- |
| `chat_task_query` | Read | `capabilities`, `list`, `read`, `task`, `task-list`, `wait`, `requests` |
| `chat_task_delegate` | Execute | `delegate` |
| `chat_task_send` | Execute | `send` |
| `chat_task_control` | Execute | `acknowledge`, `cancel`, `interrupt`, `respond`, `configure` |

Each tool uses `{operation,payload}` and rejects fields outside the selected operation's canonical body. Mutable tools map their separate `clientRequestId` to `requestId`, including receipt-backed acknowledgement on updated hosts. The legacy CLI and injected acknowledgement path preserves omission when no ID is supplied; supplied IDs remain unchanged. The injected mixed status/acknowledge tool advertises execute access because it can mutate, while public task query remains read-only. The control access class matches existing public task cancellation, terminal interruption, and per-chat execution. Provider/global Settings and secret management continue to require their separate admin tools.

Read/task-list pages default to 100 and accept limits from 1 to 200; task-list uses the returned nonnegative cursor. Query never acknowledges results. Wait accepts 1 to 200 IDs and 1 to 50 seconds, defaulting to 50 and `until:all`; a timeout does not cancel work. Task/message text is capped at 64 KiB and the body at 256 KiB. Requests require `chatId` or `taskId`. The MCP schemas list exact target, agent, policy, and operation bodies, with no arbitrary provider-option escape hatch.

Human parent binding requires `chatOrchestrationPersonParentV1` on delegate/send; task-list parent filtering is just a query. Delegation effort belongs only in `agent.options.reasoningEffort`, a nonempty string of at most 128 bytes. It and configure effort selection/reset require the independent `chatOrchestrationEffortV1` plus verified destination-model support. Default selection omits model/effort; configure alone accepts explicit null resets. Unknown provider options and credentials are rejected. The ordinary `alera chat` commands share these additive capability checks while retaining their bound lineage route.

## Background work

A chat stays working after its turn while native work the agent resumes from is open: native sub-agents, and background commands the agent marked. `backgroundWait {taskIds, waiting?}` (MCP `chat_background_wait`, CLI `alera chat background-wait`) marks or unmarks the bound caller's own background commands, resolved from its credential, and answers `{matched, unmatched}`; only Claude supports it, and other providers answer an invalid request. When the injected server is present, the Claude system prompt tells the agent when to call it, because Claude Code defers MCP tools behind ToolSearch.

Codex does not resume a parent whose turn already completed when one of its direct sub-agents finishes. The runtime then starts a parent turn itself, an automated message with `origin {kind: subagentWake}` that carries the sub-agent's outcome and final answer, but only while nothing runs, waits or is queued; otherwise the next turn reads the result natively. Claude resumes its own agent and needs no wake.

## Notifications and cancellation

`notify` is `always|settled_only|never`. Async defaults to `always`; bounded waits avoid duplicate notifications and enable a later wake after timeout. Parent wakes are durable, idempotent queued messages with a stable client message ID and an increasing delivery generation. Concurrent completions merge into a cohort. Wakes identify completed tasks; the parent reads their results separately. A wake never interrupts a running parent turn.

Cancellation interrupts the owned child turn, cancels its queued input and recursively cancels descendants. Preparation checks cancellation before launch. Already-created workspaces remain recorded and are never deleted automatically. Restart recovery reconciles tasks with the chat store and marks interrupted work explicitly; it does not retry inference automatically.

## Identity and permissions

Humans use the existing authenticated desktop/mobile host permissions. An injected MCP server binds to one chat generation using a random per-chat credential stored in a private file; persistence holds its hash. The hello connection verifies the credential and stamps `agent:<chatId>` and scope `chat:<chatId>`, ignoring caller-supplied identity. Credentials are revoked on provider switch and close. Bound agents need a live, unarchived caller turn.

Bound agents may read and message chats across known projects and hosts. They may interrupt, configure, answer requests, acknowledge results or cancel work only in their own descendant lineage. Targets cannot exceed the caller's runtime mode ceiling. Host-to-host forwarding verifies the origin chat belongs to the authenticated origin host. Credentials, provider environment and MCP tokens never appear in snapshots, events, logs or task results. This identity binding does not replace an operating system sandbox.

## Runtime and storage boundaries

`AgentChatRuntime` supplies create/list/command/send/interrupt/snapshot/subscribe and `ProviderLaunchHook` runs before each native spawn. Host-only metadata records lineage; only explicit safe lineage fields are projected to clients. `SendInput.origin` records a chat message, orchestration wake or sub-agent wake so clients can distinguish it from user input. Store tasks, wakes, receipts and credential hashes separately from terminal orchestration. Receipt identity is `(scope,verb,requestId)` plus a canonical payload digest; same payload replays, a different payload conflicts. Journal/task changes commit before broadcast.

The hub owns cross-host task routing. Each satellite owns its provider processes and chat transcript. Workspace creation uses `HubSelfClientPool` and the existing `workspace.createManaged` or `workspace.createShared` flow, including setup and mutation barriers. No additional git implementation is introduced.

## Provider tool injection

The shared provider contract carries typed stdio or HTTP MCP specifications and explicit injection capabilities. The host injects `alera mcp --runtime-dir <dir> serve --chat-credential-file <private-path>` with a stable server name. Adapters validate and translate that specification to their native session configuration. Unsupported configuration returns an explicit error and is reported in the catalog; it is never silently discarded.

Codex and Claude use native MCP configuration; Cursor uses its public bridge MCP fields; ACP variants pass servers on session new/load/resume; Muse negotiates `sessionMcp`; OpenCode installs and removes per-chat servers through its HTTP API and refuses unsafe shared-server mutation; Pi uses a documented extension bridge because its RPC runtime has no native MCP boundary. Each adapter has wire fixture tests for injection. Runtime/host binaries remain external dependencies when their source or redistribution license differs from the client port.

## UI and verification

Chat Tasks is the fourth section of the existing Activity overlay/screen, alongside Runs, Questions and Automations. Chat notices link to task details, and Open Chat/Open Workspace are explicit navigation actions. Selecting a task never changes the workspace or chat. Shared Dart DTOs and repositories live in `packages/alera_agent_chat`; native frame projection remains in Rust. Older hosts show Update Required for the section, and capability gates disable delegation controls.

Verification covers durable receipt replay/conflict, workspace strategies, cross-project routing, mode ceilings, lineage mutations, live-turn credentials/revocation, concurrent wake merging, recursive cancellation, restart reconciliation, per-provider injection, MCP catalog/CLI parity and desktop/mobile repository and widget behavior. Runtime wiring and process fixtures must be tested independently from real model inference.
