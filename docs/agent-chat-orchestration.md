# Chat orchestration

## Scope

The runtime owns orchestration between agent chats, including chats in different projects and on connected hosts. This system is separate from terminal orchestration. It uses the same chat actors, persistence, provider sessions, approvals and synchronization as `agentChat.*`. Desktop and paired mobile expose the same human controls. Neither delegation nor messages change the user's selected workspace or tab.

Delegation always names its target: an existing chat, a new chat in an existing workspace, or a new workspace with `mode: worktree|shared`. New workspaces name their project and host explicitly and go through the existing managed/shared workspace API. A child receives the supplied brief only, without copying its parent's history. Provider switches keep chat identity and lineage while changing native session generation.

## Contract

The additive capability is `chatOrchestrationV1`. Host verbs use `chatOrchestration.*`; MCP tools use the `chat_` prefix so they cannot collide with terminal tools. The verbs are `capabilities`, `delegate`, `send`, `task`, `tasks.list`, `wait`, `cancel`, `interrupt`, `requests`, `respond`, `configure`, `read` and `list`. The CLI group is `alera chat`. Receipt-backed mutations (`delegate`, `send`, `cancel`, `interrupt`, `respond` and `configure`) carry `requestId`; MCP exposes `clientRequestId` and maps it to that field. Reading a task with `acknowledge: true` acknowledges its result without a request ID.

`delegate` accepts `{task, title?, role?, notify?, mode: async|wait, waitSeconds?, requestId, agent?: {providerInstanceId?, model?, options?}, runtimeMode?, interactionMode?, target}`. A target is exactly one of `{chat:{chatId}}`, `{workspace:{workspaceId}}` or `{newWorkspace:{projectId,hostId,mode:worktree|shared,branch?,sourceBranch?,reuseExistingBranch?,name?,parentWorkspaceId?,setup:inline|deferred}}`. Worktree targets require `branch`; setup defaults to `inline`. Its response includes `{taskId,chatId?,workspaceId?,status,result?}`.

`send` accepts `{chatId,message,delivery:auto|queue,expectReply,requestId}`. With `expectReply`, it creates a message task whose completion can notify the sender. `task` reads and optionally acknowledges a result; `wait` waits for at most 50 seconds. `tasks.list` includes lineage, target, status, attention and result delivery state. `read` exposes user and assistant text and canonical plans, without provider credentials or hidden reasoning. The event `chatOrchestrationChanged {taskId,parentChatId?,childChatId?,workspaceId?}` invalidates lists on desktop and mobile.

Tasks have app-owned `taskId` distinct from `childChatId`, and states `preparing|running|needs_input|completed|failed|interrupted|cancel_requested|cancelled`. Completion follows the child's settled turn, not request acknowledgement. Results contain bounded final assistant text. Open child requests produce `needs_input`. Follow-up work produces a new task even when reusing a child chat.

## Notifications and cancellation

`notify` is `always|settled_only|never`. Async defaults to `always`; bounded waits avoid duplicate notifications and enable a later wake after timeout. Parent wakes are durable, idempotent queued messages with a stable client message ID and an increasing delivery generation. Concurrent completions merge into a cohort. Wakes identify completed tasks; the parent reads their results separately. A wake never interrupts a running parent turn.

Cancellation interrupts the owned child turn, cancels its queued input and recursively cancels descendants. Preparation checks cancellation before launch. Already-created workspaces remain recorded and are never deleted automatically. Restart recovery reconciles tasks with the chat store and marks interrupted work explicitly; it does not retry inference automatically.

## Identity and permissions

Humans use the existing authenticated desktop/mobile host permissions. An injected MCP server binds to one chat generation using a random per-chat credential stored in a private file; persistence holds its hash. The hello connection verifies the credential and stamps `agent:<chatId>` and scope `chat:<chatId>`, ignoring caller-supplied identity. Credentials are revoked on provider switch and close. Bound agents need a live, unarchived caller turn.

Bound agents may read and message chats across known projects and hosts. They may interrupt, configure, answer requests, acknowledge results or cancel work only in their own descendant lineage. Targets cannot exceed the caller's runtime mode ceiling. Host-to-host forwarding verifies the origin chat belongs to the authenticated origin host. Credentials, provider environment and MCP tokens never appear in snapshots, events, logs or task results. This identity binding does not replace an operating system sandbox.

## Runtime and storage boundaries

`AgentChatRuntime` supplies create/list/command/send/interrupt/snapshot/subscribe and `ProviderLaunchHook` runs before each native spawn. Host-only metadata records lineage; only explicit safe lineage fields are projected to clients. `SendInput.origin` records a chat message or orchestration wake so clients can distinguish it from user input. Store tasks, wakes, receipts and credential hashes separately from terminal orchestration. Receipt identity is `(scope,verb,requestId)` plus a canonical payload digest; same payload replays, a different payload conflicts. Journal/task changes commit before broadcast.

The hub owns cross-host task routing. Each satellite owns its provider processes and chat transcript. Workspace creation uses `HubSelfClientPool` and the existing `workspace.createManaged` or `workspace.createShared` flow, including setup and mutation barriers. No additional git implementation is introduced.

## Provider tool injection

The shared provider contract carries typed stdio or HTTP MCP specifications and explicit injection capabilities. The host injects `alera mcp serve --runtime-dir <dir> --chat-credential-file <private-path>` with a stable server name. Adapters validate and translate that specification to their native session configuration. Unsupported configuration returns an explicit error and is reported in the catalog; it is never silently discarded.

Codex and Claude use native MCP configuration; Cursor uses its public bridge MCP fields; ACP variants pass servers on session new/load/resume; Muse negotiates `sessionMcp`; OpenCode installs and removes per-chat servers through its HTTP API and refuses unsafe shared-server mutation; Pi uses a documented extension bridge because its RPC runtime has no native MCP boundary. Each adapter has wire fixture tests for injection. Runtime/host binaries remain external dependencies when their source or redistribution license differs from the client port.

## UI and verification

Chat Tasks is the fourth section of the existing Activity overlay/screen, alongside Runs, Questions and Automations. Chat notices link to task details, and Open Chat/Open Workspace are explicit navigation actions. Selecting a task never changes the workspace or chat. Shared Dart DTOs and repositories live in `packages/alera_agent_chat`; native frame projection remains in Rust. Older hosts show Update Required for the section, and capability gates disable delegation controls.

Verification covers durable receipt replay/conflict, workspace strategies, cross-project routing, mode ceilings, lineage mutations, live-turn credentials/revocation, concurrent wake merging, recursive cancellation, restart reconciliation, per-provider injection, MCP catalog/CLI parity and desktop/mobile repository and widget behavior. Runtime wiring and process fixtures must be tested independently from real model inference.
