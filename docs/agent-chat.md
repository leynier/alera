# Agent Chat

Agent chats are workbench tabs that talk to a coding agent through the runtime host's provider adapters instead of a terminal. They coexist with terminal tabs. The runtime host owns the provider process and the transcript, so a chat keeps running when the window closes and the same chat is driven from desktop and paired phones.

## Layers

- `packages/alera_agent_chat` (pure Dart, shared with mobile): the `agentChat.*` wire contract, the snapshot and change models, the `AgentChatThread` reducer, the timeline projection and `RuntimeAgentChatRepository` over an `AgentChatTransport`. See its [readme](../packages/alera_agent_chat/readme.md).
- `lib/src/features/agent_chat/infra`: `RuntimeHostAgentChatTransport` adapts the desktop runtime client, mapping host errors to package exceptions and the socket's connect/disconnect events to the package lifecycle events.
- `lib/src/features/agent_chat/application`: `AgentChatController` (one per open chat) reads the snapshot after subscribing to changes, applies changes by cursor, reloads on a skipped cursor, a misaligned text append or a reconnect, and keeps itself alive while a send or a response is in flight. Composer drafts live in a session-only store and are never persisted.
- `lib/src/features/agent_chat/presentation`: the tab surface, timeline, docks, composer and the New Agent Chat dialog.
- `mobile/lib/src/features/agent_chat`: phone controllers and presentation over the same package, with `MobileAgentChatTransport` adapting the direct or relay runtime connection. The phone never starts a provider process.

The runtime side is described in `rust/alera-cli/src/terminal_host/server/agent_chat_runtime/readme.md`; chat orchestration in [agent-chat-orchestration.md](agent-chat-orchestration.md).

## Workbench integration

- Tab kind `agentChat` with host-owned payload `{chatId, provider, providerInstanceId, model?}`; `agentChatId` is read as a legacy alias. The app declares `supportedTabKinds: ["agentChat"]` in its hello, so older apps never receive these tabs.
- "Agent Chat" in a pane's add-tab menu and the New Agent Chat shortcut (`Mod+Shift+T`) open a dialog to pick the provider instance, model, approval mode and plan mode. Creating the chat opens its tab in the chosen pane group and focuses it only while the person is still on that workspace.
- Closing the tab archives the chat on the runtime and stops its provider; history is kept. The New Agent Chat dialog lists the workspace's archived chats, and Reopen brings one back in a new tab.
- A chat tab shows the status dot colors agent terminals use (working, waiting for the person, failed) even while the chat is not open. The dots come from `agentChat.list` statuses kept current by each chat's session and request changes, not from terminal agent presence.
- Every entry point checks `agentChatV1`. Against an older runtime the menu entry is hidden, the shortcut explains that an update is required, and an existing chat tab shows Update Required. There is no fallback.

## Conversation

- Each turn shows the prompt, a "Worked for" divider that folds the agent's commands, edits, tool calls, reasoning and narration, then the answer. A running turn shows a live "Working for" counter and stays expanded; a finished turn with more than one action folds by default. Consecutive actions collapse into one summary line such as "Edited 2 files, ran 3 commands"; each action expands to its command, output tail, diff, tool input and result, or raw provider data.
- Approvals, MCP forms and requests the app cannot answer appear as cards in the timeline and offer exactly the decisions the runtime lists. Questions dock above the composer, with paging across several pending requests and drafts kept per request.
- Input that another chat or an orchestration wake sent renders as a notice rather than as the person's message, and never navigates anywhere.
- Desktop agent Markdown is rendered without fetching images; `http`, `https` and `mailto` links leave the app. Mobile uses the workspace Markdown viewer's remote-image URI policy and opens `http` and `https` links in the browser. Bare file paths open as workspace files on both surfaces.

Long text, reasoning and tool output are stored in bounded continuation rows. The shared timeline joins contiguous rows per stream while preserving the original item IDs used by synchronization. A history page with missing rows shows selectable partial text and a notice; loading the remaining history restores the complete message and its Markdown rendering. Automated partial prompts stay notices and do not enter prompt history.

Large native metadata keeps a redacted preview on its visible item and stores the complete redacted JSON in linked hidden rows. Hidden rows do not appear in normal snapshots, history or timeline changes. Load Full Data fetches that text explicitly through the paged `agentChat.payload` endpoint, including archived chats. Loading checks chunk order and payload consistency before exposing a bounded selectable preview and Copy Full Data. Native JSON is not decoded or pretty-printed on the UI isolate; loading and retry states remain local to the details panel.

## Composer

- Enter sends; while a turn runs the runtime queues the message (or steers when requested), and the queue dock lets any client take a queued message back. Escape stops a running turn. Arrow keys in an empty composer recall earlier prompts the person sent.
- A sent message shows immediately and is replaced by the runtime's item carrying the same client message id. A failed send keeps its id, so Retry is deduplicated by the runtime; Edit returns the text to the composer.
- The footer shows the provider (switchable only while the chat is idle with nothing pending, with confirmation), model, approval mode, plan mode and context usage. Settings apply to the next turn through `agentChat.configure`; the runtime rejects what the provider cannot honor and the reason appears above the composer.
- A dropped connection keeps the transcript readable, disables the composer and reloads the snapshot when the runtime returns. A stopped session offers the recovery actions the runtime verified (resume or start a new session); sending also resumes it.

## Known limits

- Attachments are host paths. Files picked or pasted on this machine are not uploaded to a remote workspace's host, matching the terminal composer.
- Phone photo and file attachments upload to the paired host through `mobile.promptImage.*` and `mobile.promptFile.*`; chats on another host offer only workspace files.
- Reasoning effort is not part of the runtime contract yet, so no effort selector is shown.
