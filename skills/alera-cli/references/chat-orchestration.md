# Chat Orchestration

Use `alera chat` for messages and delegated tasks between live agent chats, including targets in other projects and on connected hosts. The runtime stores task lineage and results durably. Each child receives the supplied brief only; the parent's conversation is not copied. Delegation and messages keep the user's selected workspace and tab unchanged.

## CLI

- `alera chat capabilities` lists providers with their orchestration support and reason, runtime modes, and the caller's permitted mode ceiling. Inspect support before selecting a provider.
- `alera chat list [--workspace-id <id>] [--project-id <id>] [--host-id <id>] [--include-archived]` discovers chats. Use exact ids from this output and project/workspace listings.
- `alera chat read --chat-id <id> [--limit <n>]` reads user and assistant text plus canonical plans, without hidden reasoning or credentials. The limit defaults to 100 and accepts 1 to 200 entries; check the returned truncation indicator.
- `alera chat delegate --task <brief> --target '<json>'` starts a task. Read [Targets And Provider Selection](#targets-and-provider-selection) below. Use exactly one of `--task`, `--task-file`, or `--task-stdin` for the brief.
- `alera chat send --chat-id <id> --message <text> [--delivery auto|queue] [--expect-reply]` sends a message. Queue waits behind the active turn; `--expect-reply` creates a message task whose settled result can notify the sender. Use exactly one of `--message`, `--message-file`, or `--message-stdin`.
- `alera chat task --task-id <id> [--acknowledge [--request-id <stable-id>]]` reads a task, its lineage and bounded result; acknowledge marks the delivered result as read. A supplied retry ID reaches the updated host's durable acknowledgement receipt. Omission preserves legacy no-ID acknowledgement; a read without acknowledgement does not accept a retry ID.
- `alera chat task-list` lists tasks. Filter with `--parent-chat-id`, `--child-chat-id`, `--root-task-id`, `--project-id`, `--workspace-id`, `--host-id`, repeated or comma-separated `--status`, or `--attention`. From an agent chat, a list that names no parent, child or root task shows only the tasks that chat delegated; name another lineage to read it, marked `readOnly`. `--limit` defaults to 100 and accepts 1 to 200; pass `nextCursor` back as `--cursor` for the next page.
- `alera chat wait --task-id <id> [--task-id <id> ...] [--until any|all] [--timeout-seconds <1-50>]` waits for tasks. Timeout defaults to 50 seconds; until defaults to `all`. Reuse the same task ids when waiting again.
- `alera chat cancel --task-id <id> [--reason <text>]` cancels the task, queued input, and descendants. Already-created workspaces remain recorded; cancellation does not delete them.
- `alera chat interrupt --chat-id <id> [--turn-id <id>]` interrupts a turn without archiving the chat.
- `alera chat background-wait --task-id <id>[,<id>...] [--stop-waiting]` marks background commands or Monitors your own chat started (1 to 20 ids, as shown when they started) so the chat stays working until they end. Only a chat-bound agent can call it, and only Claude chats support it; other providers answer an invalid request. Mark work you will act on when it wakes you, such as tests or a build, never a dev server or watcher. `--stop-waiting` removes the mark without stopping the task. Ids that are not running come back in `unmatched`.
- `alera chat requests [--chat-id <id>] [--task-id <id>]` lists open approval, user-input and elicitation requests. `alera chat respond --chat-id <id> --runtime-request-id <id> --response '<json>'` answers one with its offered decision or native response. When a request lists `supportsFeedback`, a `decline` or `cancel` may add `"feedback":"<text>"`, which the agent that asked receives instead of a plain refusal. Use exactly one of `--response`, `--response-file`, or `--response-stdin`.
- `alera chat configure --chat-id <id>` changes an idle chat. Pass at least one of `--provider`, `--provider-instance-id`, `--model`, `--reset-model`, `--reasoning-effort`, `--reset-reasoning-effort`, `--runtime-mode`, or `--interaction-mode`. Omission preserves model/effort; resets send an explicit null for the provider default. A concrete selection and its reset cannot be combined. Provider changes preserve chat identity and lineage but change native session generation.

All new mutations carry a retry key, generated when omitted. Pass a stable `--request-id <id>` before the first mutation if a caller may retry it. Reuse that id with the same payload after an unclear answer; the runtime replays the receipt and rejects a reused key with a different payload. The legacy `task --acknowledge` path preserves omission for older callers; explicitly supply the ID for receipt-backed acknowledgement retries.

Human callers can pass `--parent-chat-id <id>` on delegate or send to bind task/wake delivery to their originating chat. It names a human-owned origin without impersonating an agent. Bound agents retain their credentialed parent and lineage; never use this flag to substitute caller identity.

## Structured Human Requests

`alera chat --json human <operation>` accepts one bounded JSON object through `--payload`, `--payload-file`, or `--payload-stdin`, plus optional exact scope flags and `--request-id`. Operations are `capabilities`, `list`, `read`, `task`, `task-list`, `wait`, `requests`, `delegate`, `send`, `acknowledge`, `cancel`, `interrupt`, `respond`, and `configure`. Their payloads use canonical `chatOrchestration.*` fields; `task-list` maps to `tasks.list`, and `acknowledge {taskId}` maps to `task {taskId,acknowledge:true}`. Bound credentials cannot enter this route; use the lineage commands above instead, without replacing their credential.

Reads never acknowledge a result. Read/task-list pages default to 100 with limits from 1 to 200. `wait {taskIds,waitSeconds?,until?}` defaults to 50 seconds and `all`; it accepts up to 200 IDs and waits from 1 to 50 seconds. Requests require `chatId` or `taskId`. Delegation takes `task,target` and optional `parentChatId,title,role,notify,mode,waitSeconds,agent,runtimeMode,interactionMode`; send takes `chatId,message` with optional `parentChatId,delivery,expectReply`. Brief/message text is capped at 64 KiB and the whole payload at 256 KiB. Parent binding on delegate/send requires `chatOrchestrationPersonParentV1` and remains human-owned. Send uses the parent only when `expectReply:true`.

Structured human mutations receive a generated retry ID when omitted and replay durable receipts with the same ID and payload, including acknowledgement on updated hosts. Legacy no-ID acknowledgement remains compatible. Configure accepts `model:null` and `reasoningEffort:null` resets. Effort and explicit effort reset need `chatOrchestrationEffortV1`; delegation effort belongs only in `agent.options.reasoningEffort`. Caller actor/scope, arbitrary provider options, settings credentials, extra target strategies, and unknown fields are refused.

## Targets And Provider Selection

A delegation target contains exactly one of these objects:

- `{"chat":{"chatId":"..."}}` reuses an existing chat. Configure it while idle before delegating with different provider or mode choices.
- `{"workspace":{"workspaceId":"..."}}` creates a child chat in an existing workspace.
- `{"newWorkspace":{"projectId":"...","hostId":"local|<ssh-id>","mode":"worktree|shared"}}` creates a workspace through the managed/shared workspace API. Optional fields are `branch`, `sourceBranch`, `reuseExistingBranch`, `name`, `parentWorkspaceId`, and `setup` (`inline` or `deferred`, default `inline`). Name the project and host explicitly.

`--agent '<json>'` selects a provider with `providerInstanceId`, optional `model`, and optional `options`. The only verified option is `reasoningEffort`, as a nonempty string in `agent.options`; it requires `chatOrchestrationEffortV1` plus the destination model's support. Omit it for the default; never put credentials or permission overrides in options. `--runtime-mode` accepts `approval-required`, `auto-accept-edits`, `auto`, or `full-access`; it cannot exceed a bound caller's current ceiling. `--interaction-mode` is `default` or `plan`.

Delegation defaults to `--mode async`; use `--mode wait --wait-seconds <1-50>` for a bounded wait. `--notify` accepts `always`, `settled_only`, or `never`; async defaults to `always`. A timeout leaves the task running. Keep its returned task/chat/workspace ids and inspect or wait again rather than redelegating.

A Codex chat whose turn already completed is resumed by the runtime when one of its direct sub-agents finishes, with an automated message carrying the sub-agent's outcome and final answer; a turn that is running or queued reads the result natively instead.

Completion follows the child's settled turn, not request acknowledgement. Open child requests set the task to `needs_input`. Follow-up delegation creates a new task even when it reuses a chat. Completion notifications queue behind an active parent turn and identify task ids; read the result separately with `alera chat task`.

## Chat-bound MCP

The runtime injects `alera mcp --runtime-dir <dir> serve --chat-credential-file <private-path>` into a supported provider session. It exposes only the 14 credential-bound chat tools (the original 13 plus `chat_background_wait`), `list_projects`, and `list_workspaces`, with no resources or subscriptions. The ordinary local server and cloud MCP catalog expose separate human Agent Chat controls and four public task tools but exclude the injected tools. Human task tools are `chat_task_query`, `chat_task_delegate`, `chat_task_send`, and `chat_task_control`; each uses an explicit operation and exact canonical payload, read/execute access, and the structured human CLI route. They never fabricate agent credentials. Direct lifecycle and Settings operations use [agent chats](agent-chats.md), without extending a bound agent's authority.

The credential is read from the private file for the host handshake; the secret never appears in command arguments. The host derives the actor and scope, requires a live unarchived caller turn, and revokes credentials on provider switch or close. Do not fall back to an unbound server when this credential is missing or invalid. MCP `clientRequestId` maps to CLI `--request-id`.

Bound agents may read, delegate to, and message chats across known projects and hosts within their mode ceiling. Interrupting, configuring, answering requests, or cancelling work requires the caller's own chat or descendant lineage. This identity binding does not replace the operating system sandbox.
