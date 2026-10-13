# Chat Orchestration

Use `alera chat` for messages and delegated tasks between live agent chats, including targets in other projects and on connected hosts. The runtime stores task lineage and results durably. Each child receives the supplied brief only; the parent's conversation is not copied. Delegation and messages keep the user's selected workspace and tab unchanged.

## CLI

- `alera chat capabilities` lists providers with their orchestration support and reason, runtime modes, and the caller's permitted mode ceiling. Inspect support before selecting a provider.
- `alera chat list [--workspace-id <id>] [--project-id <id>] [--host-id <id>] [--include-archived]` discovers chats. Use exact ids from this output and project/workspace listings.
- `alera chat read --chat-id <id> [--limit <n>]` reads user and assistant text plus canonical plans, without hidden reasoning or credentials. The limit defaults to 100 and accepts 1 to 200 entries; check the returned truncation indicator.
- `alera chat delegate --task <brief> --target '<json>'` starts a task. Read [Targets And Provider Selection](#targets-and-provider-selection) below. Use exactly one of `--task`, `--task-file`, or `--task-stdin` for the brief.
- `alera chat send --chat-id <id> --message <text> [--delivery auto|queue] [--expect-reply]` sends a message. Queue waits behind the active turn; `--expect-reply` creates a message task whose settled result can notify the sender. Use exactly one of `--message`, `--message-file`, or `--message-stdin`.
- `alera chat task --task-id <id> [--acknowledge]` reads a task, its lineage and bounded result; acknowledge marks the delivered result as read.
- `alera chat task-list` lists tasks. Filter with `--parent-chat-id`, `--child-chat-id`, `--root-task-id`, `--project-id`, `--workspace-id`, `--host-id`, repeated or comma-separated `--status`, or `--attention`. `--limit` defaults to 100 and accepts 1 to 200; pass `nextCursor` back as `--cursor` for the next page.
- `alera chat wait --task-id <id> [--task-id <id> ...] [--until any|all] [--timeout-seconds <1-50>]` waits for tasks. Timeout defaults to 50 seconds; until defaults to `all`. Reuse the same task ids when waiting again.
- `alera chat cancel --task-id <id> [--reason <text>]` cancels the task, queued input, and descendants. Already-created workspaces remain recorded; cancellation does not delete them.
- `alera chat interrupt --chat-id <id> [--turn-id <id>]` interrupts a turn without archiving the chat.
- `alera chat requests [--chat-id <id>] [--task-id <id>]` lists open approval, user-input and elicitation requests. `alera chat respond --chat-id <id> --runtime-request-id <id> --response '<json>'` answers one with its offered decision or native response. Use exactly one of `--response`, `--response-file`, or `--response-stdin`.
- `alera chat configure --chat-id <id>` changes an idle chat. Pass at least one of `--provider`, `--provider-instance-id`, `--model`, `--runtime-mode`, or `--interaction-mode`. Provider changes preserve chat identity and lineage but change native session generation.

All mutations carry a retry key, generated when omitted. Pass a stable `--request-id <id>` before the first mutation if a caller may retry it. Reuse that id with the same payload after an unclear answer; the runtime replays the receipt and rejects a reused key with a different payload.

## Targets And Provider Selection

A delegation target contains exactly one of these objects:

- `{"chat":{"chatId":"..."}}` reuses an existing chat. Configure it while idle before delegating with different provider or mode choices.
- `{"workspace":{"workspaceId":"..."}}` creates a child chat in an existing workspace.
- `{"newWorkspace":{"projectId":"...","hostId":"local|<ssh-id>","mode":"worktree|shared"}}` creates a workspace through the managed/shared workspace API. Optional fields are `branch`, `sourceBranch`, `reuseExistingBranch`, `name`, `parentWorkspaceId`, and `setup` (`inline` or `deferred`, default `inline`). Name the project and host explicitly.

`--agent '<json>'` selects a provider with `providerInstanceId`, optional `model`, and optional `options`. `--runtime-mode` accepts `approval-required`, `auto-accept-edits`, `auto`, or `full-access`; it cannot exceed a bound caller's current ceiling. `--interaction-mode` is `default` or `plan`.

Delegation defaults to `--mode async`; use `--mode wait --wait-seconds <1-50>` for a bounded wait. `--notify` accepts `always`, `settled_only`, or `never`; async defaults to `always`. A timeout leaves the task running. Keep its returned task/chat/workspace ids and inspect or wait again rather than redelegating.

Completion follows the child's settled turn, not request acknowledgement. Open child requests set the task to `needs_input`. Follow-up delegation creates a new task even when it reuses a chat. Completion notifications queue behind an active parent turn and identify task ids; read the result separately with `alera chat task`.

## Chat-bound MCP

The runtime injects `alera mcp --runtime-dir <dir> serve --chat-credential-file <private-path>` into a supported provider session. It exposes only the 13 `chat_*` tools, `list_projects`, and `list_workspaces`, with no resources or subscriptions. The ordinary local server and cloud MCP catalog keep the terminal-oriented tools; they do not expose chat tools.

The credential is read from the private file for the host handshake; the secret never appears in command arguments. The host derives the actor and scope, requires a live unarchived caller turn, and revokes credentials on provider switch or close. Do not fall back to an unbound server when this credential is missing or invalid. MCP `clientRequestId` maps to CLI `--request-id`.

Bound agents may read, delegate to, and message chats across known projects and hosts within their mode ceiling. Interrupting, configuring, answering requests, or cancelling work requires the caller's own chat or descendant lineage. This identity binding does not replace the operating system sandbox.
