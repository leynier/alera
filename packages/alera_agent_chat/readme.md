# alera_agent_chat

Agent chat domain shared by the Alera desktop and mobile apps. It holds the `agentChat.*` wire contract of the runtime host, the client-side reducer, and the timeline projection both apps render, so a chat looks and behaves the same on every client. Pure Dart: no Flutter, no `dart:io`, no state management.

## Contents

- `AgentChatWire`: capability (`agentChatV1`), tab kind and payload keys, event names and verbs.
- Models parsed from runtime JSON: `AgentChatSnapshot`, `AgentChatItem`, `AgentChatTurn`, `AgentChatRequest`, `AgentChatSession`, `AgentChatQueueEntry`, `AgentChatProviderInstance`, `AgentChatSummary`.
- `AgentChatThread`: a snapshot plus every later `agentChatChanged`, applied by cursor. `apply` returns `AgentChatApplied`, `AgentChatIgnored` (stale or foreign) or `AgentChatGapNeedsSnapshot` (a skipped cursor or a misaligned text append). Text append offsets are UTF-16 code units.
- `AgentChatTimelineProjection`: turn sections (prompt, "Worked for" activity, answers, plan checklist), standalone notices, approval entries, docked questions and optimistic outgoing messages.
- Continuation projection joins contiguous text, reasoning and output streams without changing wire item IDs. Incomplete history stays explicitly partial; hidden metadata rows never enter the timeline.
- Optional `AgentChatPayloadRepository`, verified payload pages and explicit `loadPayloadJson` preserve complete redacted JSON as text. Chunk order and revisions are checked without decoding large native data on the UI isolate.
- `AgentChatRepository` and `RuntimeAgentChatRepository`, which speaks the wire over an `AgentChatTransport`. Each app adapts its own runtime client to that transport and emits `AgentChatTransportEvents.connected` and `disconnected` for its connection.
- Orchestration task, target, result and capability models, `ChatOrchestrationRepository`, live task lists and delegation-form validation for `chatOrchestration.*`. These support existing chats, new chats in existing workspaces, and explicitly selected worktree or shared workspaces across projects and hosts.

## Rules

- Mutations take a caller-allocated id (`requestId`, or `clientMessageId` for a send) so a retry after a dropped connection replays the runtime's receipt.
- Chat-scoped verbs carry the workspace id so the hub can route a remote workspace's chat to its host.
- Every call checks `agentChatV1` first and throws `AgentChatUpdateRequired` against an older runtime; there is no fallback.
- Orchestration checks `chatOrchestrationV1` independently. Changes refresh matching task views without navigating, and opening a parent-owned task does not acknowledge the result on its parent's behalf.

The runtime side of the contract is described in `rust/alera-cli/src/terminal_host/server/agent_chat_runtime/readme.md`.
