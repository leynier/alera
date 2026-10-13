# Chat Orchestration

These tools are available only in the narrowed MCP server the runtime injects into a live agent chat. They are absent from the cloud MCP catalog and the ordinary local server. The injected server also exposes `list_projects` and `list_workspaces` for target discovery, with no resources, subscriptions, or terminal orchestration tools.

## Identity And Authority

The runtime reads a private credential file and binds every call to one chat generation. The host derives actor and scope; callers cannot supply either. A bound caller needs a live, unarchived turn. Credentials expire on provider switch or close; never replace a failed binding with an unbound server.

Bound agents can read, delegate to, and message chats across known projects and connected hosts within their current runtime mode ceiling. Interrupting, configuring, answering requests, or cancelling work requires their own chat or descendant lineage. The credential does not replace an operating system sandbox.

## Choose A Target And Delegate

- `chat_capabilities` lists providers, orchestration support and reasons, runtime modes, and the caller's ceiling. Check support before choosing a provider.
- `chat_list` discovers chats with optional `workspaceId`, `projectId`, `hostId`, and `includeArchived` filters. Use exact chat, project, workspace, and provider instance ids from the listings.
- `chat_read` returns user and assistant text plus canonical plans. `limit` defaults to 100, accepts 1 to 200 entries, and the result reports truncation. Hidden reasoning and credentials are excluded.
- `chat_delegate` starts a durable task with a brief in `task` and exactly one `target`. The child receives only that brief, not its parent's conversation. It returns task, chat and workspace ids; keep them for retries and follow-up.

Targets are `{"chat":{"chatId":"..."}}` for an existing chat, `{"workspace":{"workspaceId":"..."}}` for a new chat in an existing workspace, or `{"newWorkspace":{"projectId":"...","hostId":"local|<ssh-id>","mode":"worktree|shared"}}` for a new workspace. New workspaces use the existing managed/shared workspace API. Their optional fields are `branch`, `sourceBranch`, `reuseExistingBranch`, `name`, `parentWorkspaceId`, and `setup` (`inline` or `deferred`, default `inline`). Name project and host explicitly.

Optional delegation fields are `title`, `role`, `agent` (`providerInstanceId`, optional `model` and `options`), `runtimeMode`, `interactionMode`, `notify`, `mode`, and `waitSeconds`. Runtime modes are `approval-required`, `auto-accept-edits`, `auto`, and `full-access`; none may exceed the caller's ceiling. Interaction modes are `default` and `plan`. Configure an idle existing chat before delegating with a different provider or mode.

`mode` defaults to `async`; `wait` waits for at most 50 seconds. `notify` is `always`, `settled_only`, or `never`; async defaults to `always`. A timed-out wait leaves the task running. Follow it by id instead of delegating again. Neither delegation nor messages changes the user's selected workspace or tab.

## Follow Work And Send Messages

- `chat_task_status` reads a task's lineage, state and bounded final result. `acknowledge` marks a delivered result as read. Completion follows the child's settled turn, not the initial request acknowledgement.
- `chat_task_wait` waits for `taskIds`, with `until` `any` or `all` (default `all`) and `timeoutSeconds` from 1 to 50 (default 50). Repeat with the same ids while work continues.
- `chat_task_list` filters by `parentChatId`, `childChatId`, `rootTaskId`, `projectId`, `workspaceId`, `hostId`, `statuses`, or `attention`. `limit` defaults to 100 and accepts 1 to 200; pass `nextCursor` back as `cursor` for the next page.
- `chat_send` sends `message` to `chatId`. `delivery` is `auto` (default) or `queue`, which waits behind an active turn. `expectReply` creates a message task whose settled result can notify the sender.

Follow-up delegation creates a new task even when it reuses a chat. Completion notifications queue behind a parent's active turn and identify task ids; read results separately. Open child requests set a task to `needs_input`.

## Control Owned Work

- `chat_task_cancel` takes `taskId` and optional `reason`, cancels queued input, interrupts its child turn, and recursively cancels descendants. Already-created workspaces remain recorded and are not deleted automatically.
- `chat_interrupt` takes `chatId` and optional `turnId`, interrupting the active turn without archiving its chat.
- `chat_requests` lists open approval, user-input and elicitation requests, optionally filtered by `chatId` or `taskId`.
- `chat_respond` answers `runtimeRequestId` for `chatId` with the exact offered decision or native object in `response`.
- `chat_configure` changes an idle chat. Pass `chatId` and at least one of `provider`, `providerInstanceId`, `model`, `runtimeMode`, or `interactionMode`. Provider changes preserve chat identity and lineage while changing native session generation.

Every mutation accepts `clientRequestId`. Choose a stable id before the first call and reuse it with the same payload after an unclear answer. The runtime replays its durable receipt; a reused key with a different payload conflicts. Do not retry with a new key when the previous mutation may have succeeded.
