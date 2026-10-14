# Human Chat Tasks

Four public tools call the existing chat orchestration runtime as an authenticated human. They never impersonate an agent or create a chat credential. Provider/global Settings still use the separate administrative tools in the `alera-mcp` skill. Private injected chat tools retain their own credentialed lineage and cannot call these human tools.

Each call takes `{operation,payload}` with an exact operation-specific body. The cloud edge adds its normal `runtime` selector. Reads require read access; delegate, send, and controls require full/execute access, matching existing public task, terminal, and workspace-launch permissions. Unknown fields, supplied actor/scope, and arbitrary provider options are refused. The whole payload is capped at 256 KiB; task/message text is capped at 64 KiB and travels on stdin, never command arguments.

## Read And Wait

`chat_task_query` offers these read-only operations:

| Operation | Payload | Result |
| --- | --- | --- |
| `capabilities` | Optional `workspaceId,hostId` | Provider orchestration support and runtime ceilings. |
| `list` | Optional `workspaceId,projectId,hostId,includeArchived` | Human-visible chats with lineage. |
| `read` | `chatId,limit?` | Bounded user/assistant text and plans; hidden reasoning and credentials excluded. |
| `task` | `taskId` | One task, its lineage, state, and bounded result; never acknowledges. |
| `task-list` | Optional `parentChatId,childChatId,rootTaskId,workspaceId,projectId,hostId,statuses,attention,limit,cursor` | Task pages with `nextCursor`. |
| `wait` | `taskIds,waitSeconds?,until?` | Current tasks and timeout state; work can remain running. |
| `requests` | `chatId` or `taskId` | Open approval, input, and elicitation requests. |

Read and task-list limits default to 100 and accept 1 to 200. Cursor is a nonnegative integer returned by the runtime. Wait accepts 1 to 200 task IDs, defaults to 50 seconds and `until:all`, and accepts `waitSeconds` from 1 to 50 with `until:any|all`. Repeat a bounded wait with the same IDs while work continues. Read tools reject acknowledgement writes.

## Delegate And Send

`chat_task_delegate` uses `operation:delegate`. Its body needs `task` and exactly one `target`: `{"chat":{"chatId":"..."}}`, `{"workspace":{"workspaceId":"..."}}`, or `{"newWorkspace":{"projectId":"...","hostId":"local|<ssh-id>","mode":"worktree|shared"}}`. A worktree needs `branch`. New-workspace optional fields are `sourceBranch,reuseExistingBranch,name,parentWorkspaceId,setup`; `setup` is `inline` (default) or `deferred`. These are ordinary managed/shared workspace operations, with no alternate Git implementation.

Optional delegation fields are `parentChatId,title,role,notify,mode,waitSeconds,agent,runtimeMode,interactionMode`. Mode defaults to `async`; `wait` returns after at most 50 seconds. Notify is `always`, `settled_only`, or `never`, defaulting to `always` for async and `settled_only` for wait. The child receives only the brief; the parent's conversation is not copied. Keep task/chat/workspace IDs and follow them instead of repeating delegation after a timeout. Creation/admission is distinct from settled completion, provider authentication, and inference success.

An agent selection contains optional `providerInstanceId,model,options`. Omit model for the instance/provider default. The only option is `agent.options.reasoningEffort`, a nonempty string of at most 128 bytes, requiring `chatOrchestrationEffortV1` and the destination model's verified support. Top-level or `agent.reasoningEffort`, credentials, and policy overrides inside options are invalid. An existing chat retains its provider and runtime policy; configure an eligible idle chat explicitly before requesting incompatible settings.

`chat_task_send` uses `operation:send` and body `{chatId,message,parentChatId?,delivery?,expectReply?}`. Delivery is `auto` (default) or `queue`. `expectReply:true` creates a message task whose settled result can notify the originating chat.

Human `parentChatId` on delegate/send requires `chatOrchestrationPersonParentV1` and an existing unarchived chat. It binds the task dock, lineage, and idle-only wake while the actor stays the human. Omission makes the task standalone. Send ignores the parent without `expectReply:true`. Never invent an agent sender or credential. Delegation, sending, and background wake delivery never select a workspace or tab; wakes never interrupt or steer an active parent turn.

## Control And Retry

`chat_task_control` offers these explicit operations:

- `acknowledge {taskId}` marks a result read. Its explicit `clientRequestId` reaches the updated host's durable acknowledgement receipt. Legacy clients that omit the host request ID retain their compatible no-ID update.
- `cancel {taskId,reason?}` cancels queued input, interrupts its child turn, and recursively cancels descendants. Created workspaces are kept.
- `interrupt {chatId,turnId?}` interrupts a turn without archiving the chat.
- `respond {chatId,runtimeRequestId,response}` uses exactly the decisions or native response the runtime offered.
- `configure {chatId,provider?,providerInstanceId?,model?,reasoningEffort?,runtimeMode?,interactionMode?}` needs at least one selection field. Model/effort omission preserves selection; explicit null resets to the provider default, without empty IDs. Effort selection/reset requires `chatOrchestrationEffortV1` and actual provider support. Runtime modes are `approval-required`, `auto-accept-edits`, `auto`, or `full-access`; interaction mode is `default` or `plan`.

Every mutable tool accepts `clientRequestId` outside its payload. Choose a stable ID before the first attempt and reuse it with identical fields after a timeout or unclear result. Do not supply `requestId` in the body; it maps from that separate retry key. Delegate, send, cancel, interrupt, respond, configure, and explicit-ID acknowledgement replay durable receipts on updated hosts and conflict on changed payloads under the same key. Legacy no-ID acknowledgement remains compatible. Controls require the user's scope and preserve host-derived identity; they do not grant provider Settings or secret administration.
