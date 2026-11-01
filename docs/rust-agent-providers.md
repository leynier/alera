# Rust Agent Providers

The Rust workspace contains provider adapters, a common lifecycle/event contract, SDK client ports, and shared process/HTTP transports. The runtime-host sidecar uses these crates for persistent agent chats on desktop and paired mobile. Flutter consumes the host's chat snapshots and changes through the shared Dart package; provider executables remain owned by the host. Reference submodules are development inputs only.

## Contract And Ports

The development contract reference is [reference_projects/t3code](../reference_projects/t3code), particularly `packages/contracts/src/providerRuntime.ts`, `providerPolicy.ts`, and `packages/provider-core/src/server/ProviderAdapter.ts`. The reference revision is recorded by the repository gitlink. Implementation code uses provider-neutral names and does not import reference source files at runtime.

Each port records its upstream repository, source version, license, supported surface and exclusions in its lowercase `readme.md`:

- [Claude client](../rust/claude-agent-sdk/readme.md): the provider-facing Python SDK stream-json/control layer; requires a separately installed Claude CLI.
- [Muse client](../rust/muse-agent-sdk/readme.md): the public MIT SDK/MSP client and protocol declarations; requires a separately installed Muse host.
- [OpenCode client](../rust/opencode-agent-sdk/readme.md): the public MIT HTTP/SSE clients for the legacy and 2.x server APIs.
- [Cursor client](../rust/cursor-agent-sdk/readme.md): the public MIT `sdk.v1` bridge protocol client. The proprietary TypeScript SDK is not copied or ported. The official external bridge runs that SDK; provision one that embeds `@cursor/sdk` 1.0.38 or later so long-context model tiers send Max Mode.
- [ACP client](../rust/agent-client-protocol/readme.md): bidirectional JSON-RPC client and session protocol over JSON lines.

Copyright notices remain in the corresponding license files. MIT licenses for client code or protocol declarations do not establish a license for a separately distributed provider executable. The libraries accept externally installed/configured executables; they do not bundle proprietary runtimes.

## Crates

| Crate | Responsibility |
| --- | --- |
| `alera-agent-transport` | Injectable JSON transport, bounded JSON-lines subprocesses, managed HTTP-server processes, cleanup and scripted mocks. |
| `alera-agent-http` | Injectable HTTP requests and byte streams, request/response limits, deadlines, streaming and mocks. |
| `alera-provider-protocol` | Provider lifecycle, capabilities, policies, requests, canonical events, raw envelopes and validation. |
| `alera-provider-codex` | Codex app-server adapter. |
| `claude-agent-sdk`, `alera-provider-claude` | Claude client port and provider adapter. |
| `agent-client-protocol`, `alera-provider-acp` | ACP client and common adapter runtime. |
| `alera-provider-grok` | Grok ACP launch/auth/policy configuration and adapter. |
| `alera-provider-antigravity` | Antigravity ACP launch/profile/auth/policy configuration and adapter. |
| `alera-provider-acp-registry` | Configurable ACP agent recipes and adapter. |
| `muse-agent-sdk`, `alera-provider-muse` | MSP client port and Muse adapter. |
| `opencode-agent-sdk`, `alera-provider-opencode` | OpenCode HTTP/SSE client port and adapter. |
| `cursor-agent-sdk`, `alera-provider-cursor` | Connect bridge client and Cursor adapter. |
| `alera-provider-pi` | Pi JSON-lines RPC adapter. |

Process-backed libraries share `alera-core::login_shell_environment` and windowless spawn helpers. Explicit per-call environment overrides take precedence, including PATH. Hydrated environment values remain in memory and are not logged. HTTP and streaming clients can be injected for deterministic tests.

## Shared Boundary

`Provider` exposes initialization, session start/resume, turn submission, interruption, request responses, event consumption and closure. `ProviderCapabilities` reports implemented operations. Unsupported operations or policy/input combinations return explicit errors rather than being silently ignored. Each provider retains its native wire semantics and server-authoritative terminal conditions.

Caller-owned `threadId` is separate from the persistent native session/thread ID. Events preserve native identities in `providerRefs` and original messages in `raw`. Native string/integer request IDs remain distinct. Local turn IDs are synthetic where the provider has no native turn identity.

The provider boundary does not allocate persisted application turn, item or request IDs. The runtime host allocates them and stores mappings by chat generation and process epoch, retaining native references separately. A provider restart cannot alias an earlier request or item, and numeric and string request IDs remain distinct.

Event payloads remain JSON to preserve provider extensions. `ProviderEvent::validate` checks envelopes and core normalized payload invariants. Unknown provider kinds, event names and native frames survive forward-compatible parsing. A callback answer must match the pending request and its supported response shape; an interrupt acknowledgement does not establish terminal completion.

A failed `turn.completed` carries the agent's own text as `errorMessage` and a structured native error as `error {code, data}`. ACP fills both from a failed prompt RPC and, for every ACP agent, from an idle `state_update` with `stopReason: "error"`, the way ACP v2 agents report a failed prompt; a failed Grok completion without error text falls back to its `agentResult`. On every ACP v2 agent (an `initialize` result with `info` or `capabilities`), a prompt response without a stop reason only accepts the prompt and the root idle `state_update` ends the turn; a response with a stop reason, or an RPC error, still ends it, and the idle such a turn may still owe does not end the next one. An idle error while no turn runs becomes `runtime.error` (`message`, `code`, `data`) unless the last turn failed. An ACP tool call the agent reports as `cancelled` completes its item as failed.

A provider advertises its slash commands with `session.commands.updated`, whose `commands` list (`name`, optional `description`, optional `input.hint`, the shape of T3 Code's `ServerProviderSlashCommand`) replaces the previous one. `ProviderSlashCommandsUpdate::new` trims names, drops a leading slash and names that cannot be typed as one token, merges case-insensitive duplicates and caps the list. ACP maps `available_commands_update`; Claude reports the commands its CLI answers `initialize` with (`ClaudeClient::server_info`), falling back to the bare `slash_commands` names of `system/init`. Pi lists `get_commands` after T3 Code's builtin `/compact`, which it sends as the RPC `compact` command. Codex lists `/compact` and runs it through `thread/compact/start`, adopting the turn Codex starts. OpenCode lists `/compact` and its server's commands and sends a prompt that opens with a known one through its command route. The runtime keeps the latest list in the chat's `session.commands`, clears it on a provider switch, and leaves expansion to the provider, which reads a prompt that starts with `/name`.

A provider with a long-running goal (Codex `/goal`) reports it with `session.goal.updated`, whose `goal` (`objective`, `status` of `active|paused|blocked|usage_limited|budget_limited|complete`, optional `tokensUsed`, `tokenBudget`, `timeUsedSeconds`, the shape of T3 Code's `OrchestrationV2ProviderGoal`) or `null` replaces the previous one. `parse_goal_command` and `GoalCommand::stops_active_turn` are T3 Code's `parseGoalCommand` and `goalCommandStopsActiveRun`. While a goal is active the Codex adapter holds a completed root `turn.completed` for 5 seconds: when Codex starts the next turn inside that window the completion carries `goalContinuation: {nextTurnId}` and the following `turn.started` carries `goalContinuation: true`, so the host continues its run into that turn; otherwise the adapter pauses the goal and releases the completion. A root turn Codex starts with no run to own it is paused, interrupted and never surfaced.

Skills (`ProviderSkill`, T3 Code's `ServerProviderSkill`) reach clients through `agentChat.skills`. A live provider reports them with `session.skills.updated` (Codex `skills/list` after start and after `skills/changed`, ACP registry `$` commands, Pi `get_commands` skill entries); otherwise each adapter crate discovers them before a session: Claude Code, Cursor and Antigravity scan their skill folders, Grok runs `grok inspect --json`, Codex runs `probe_skills` against a short-lived app-server and OpenCode reads its server's skill API. Prompts keep the `$name` mentions clients insert; each adapter rewrites them as T3 Code does (Codex writes every mention with `$`, Claude Code dispatches the last one as a `/name` text block, Cursor turns known ones into `/name`, Grok only a leading one, OpenCode 2.x sends `skills` ids, the rest send the text unchanged). The mention grammar and frontmatter reader are shared in `alera-provider-protocol`. See [Agent Chat Harness Parity](agent-chat-harness-parity.md).

Native background work arrives as `task.*` events. `awaited: true` marks work the agent resumes from (native sub-agents), `parentTaskId` names the sub-agent whose own work a task is, and a failed `turn.completed` with `childTurnsContinue: true` says native child turns outlive it. `wakesParent: true` on a `task.completed` says the native parent only reads the result on its next turn; Codex sets it for a direct child thread that completes or fails, and reports grandchildren as tasks with `parentTaskId` that never end the root turn. Claude Code resumes its own agent from a task notification, so it never sets it. A background command is never awaited by itself: the optional `Provider::await_background_tasks` confirms which of the ids the agent named are running background commands (Claude's `local_bash` tasks), and the runtime holds the marks. Providers without it return `Unsupported`. The optional `Provider::stop_subagent` stops one native sub-agent by the task id its task events carry: Codex interrupts the child thread's running turn, Claude sends `stop_task`, an ACP agent with native child sessions gets `session/cancel` for the child session; others return `Unsupported`. `Provider::subagent_capabilities` says what a live session can do with them beyond the static traits. Codex streams a child thread's own items and deltas as items of the session with `parentToolUseId` naming the call that spawned the child (`subagentThreadId` names the child), and puts the spawn's `model` and `reasoningEffort` on the child's task events; the child's prompt stays on the spawning call. With `AcpProviderConfig::native_child_sessions` (the registry sets it for Claude Agent, whose launch selects the ACP v2 preview with `CLAUDE_AGENT_ACP_EXPERIMENTAL_V2=1` unless its environment sets it) and an ACP v2 `initialize`, the ACP adapter follows the agent's work state (the prompt response only accepts; the root idle ends the turn) and projects child sessions the same way: `subagent_update` and `session_message` link each child to the Agent/Task call that delegated to it, its items and deltas carry `parentToolUseId`, and its state becomes awaited `task.*` events keyed by that call. Pi nests a call that a tool makes through `ctx.executeTool()` (a codemode script, tagged `parentToolCallId`) under its caller the same way: the call's items carry `parentToolUseId`, and the caller's own `task.*` events, keyed by its call id and not awaited, open at its first nested call and settle when it ends or its turn settles. Work the agent starts on its own while no turn runs opens a `turn.started` with `agentStarted.origin: backgroundContinuation`, which the runtime adopts as the running turn.

A task event may carry `workflow` (`SubagentWorkflow`): what one frame reported of a provider-native workflow, its name, run handles, the files root the provider keeps run files under, phases, members and usage. The Claude adapter reads it from Claude Code's undocumented `local_workflow` frames and the Workflow tool's launch acknowledgement, dropping anything that does not parse and reading an unknown member state as running; the host folds frames with `SubagentWorkflow::merge`.

Context compaction is one `context_compaction` item for both Codex and Claude: Claude reports it from `system/status` (`compacting`, then `compact_result`) and `compact_boundary`, with `data.trigger`, `data.outcome` (`running`, `completed`, `failed` or `stopped`) and the boundary's token counts. Claude API retries are one live `error` item with `data.attempt`, `maxAttempts`, `retryDelayMs` and `code`. Live context usage travels on `thread.token-usage.updated` as `contextTokens`, `contextWindow` and, only when the provider knows where it compacts on its own, `autoCompactTokens` (Claude with `CLAUDE_CODE_AUTO_COMPACT_WINDOW` set); the turn's `tokenUsage` repeats them, and the host keeps the count and context groups apart. Codex reports only the rate-limit windows that changed, Claude reports a rejected limit without utilization as a full window with its reset time, and the host merges windows by id.

Questions may carry option previews in the request payload's `optionPreviews` side channel (`USER_INPUT_OPTION_PREVIEWS`), `{questionId: [preview | null, ...]}`; the host attaches them to the options of the request view. Every local attachment is named in the prompt text by `text_with_attachment_paths` (`[Attached file "name" is saved at: path]`), so an adapter that cannot take a file natively still tells the agent where it is. Codex `imageGeneration` items become byte-free `image_generation` items with `data.savedPath`, and a root turn's completion waits for its images to render.

JSON-lines writes retain their frame, offset and deadline when the caller cancels a send. An identical retry completes the pending frame once, while a different send finishes it before writing the next frame. A hard write error closes the damaged stream. Process cleanup remains resumable when a close operation is cancelled. JSON-lines stdout reserves one terminal-error slot in its bounded queue and waits up to `ProcessConfig.shutdown_timeout` for receiver capacity before reporting `OutputQueueFull`, allowing a draining receiver to consume bursts without overflow.

## Runtime Integration

The runtime catalog exposes nine provider kinds: `codex`, `claudeAgent`, `cursor`, `grok`, `opencode`, `antigravity`, `pi`, `muse` and `acpRegistry`. The common ACP crate supplies shared implementation for its provider wrappers rather than a tenth catalog entry.

The host projects provider events into durable chats, turns, timeline items and pending requests. SQLite receipts make retries idempotent, committed changes carry a per-chat cursor, and clients reload a snapshot after reconnecting or detecting a gap. Historical turns live in separate rows so long chats do not grow an unbounded snapshot header. Closing a chat archives its history and stops its session; recovery and reopening are explicit operations.

The same runtime powers chat orchestration across projects and workspaces. Its ledger and credentials are separate from terminal orchestration. Per-chat MCP injection uses typed, host-only server specifications and reports unsupported provider transports before startup. Public views exclude launch environments and credential files. See [Agent Chats](agent-chat.md), [Chat Orchestration](agent-chat-orchestration.md), and the host [wire contract](../rust/alera-cli/src/terminal_host/server/agent_chat_runtime/readme.md).

## Remote Chat Resources

Attachment uploads terminate on the chat owner and remain human/caller/workspace/chat scoped. The hub preserves originating identity, and the owner resolves completed receipts into provider paths. Upload I/O and digest checks run behind worker boundaries; native provider adapters do not copy client files. Pi names every attachment in its prompt by the saved path, as T3 Code does, and also sends local PNG, JPEG, GIF and WebP images of up to 10 MiB as native base64 images within half of its 64 MiB frame limit.

Provider Setup on a satellite requires `agentChatRemoteProviderSetupV1` on both runtimes. An authenticated desktop selects only an instance and verified action; the hub derives authority and the owner hydrates its own login-shell environment, profile and credentials. Phones, bound agent credentials and reverse channels cannot invoke setup. Old hosts refuse remote setup explicitly.

## Validation

Run from `rust/` to select the pinned toolchain. The following checks cover the provider layer without building the native app:

```sh
cargo fmt --all -- --check
cargo test --locked -p alera-agent-transport -p alera-agent-http -p alera-provider-protocol
cargo test --locked -p claude-agent-sdk -p muse-agent-sdk -p opencode-agent-sdk -p cursor-agent-sdk -p agent-client-protocol
cargo test --locked -p alera-provider-codex -p alera-provider-claude -p alera-provider-acp -p alera-provider-grok -p alera-provider-antigravity -p alera-provider-acp-registry -p alera-provider-pi -p alera-provider-muse -p alera-provider-opencode -p alera-provider-cursor
```

Run Clippy with the same package selection, `--all-targets -- -D warnings`. Tests use scripted native frames, local loopback HTTP servers and portable fake subprocesses. They exercise handshake ordering, response correlation, framing, event mapping, approvals/input, cancellation, failure paths and cleanup without model requests or credentials. Live CLI/account compatibility remains a separate verification.
