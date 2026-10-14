# Agent Chat

Agent chats are workbench tabs that talk to a coding agent through the runtime host's provider adapters instead of a terminal. They coexist with terminal tabs. The runtime host owns the provider process and the transcript, so a chat keeps running when the window closes and the same chat is driven from desktop and paired phones.

## Layers

- `packages/alera_agent_chat` (pure Dart, shared with mobile): the `agentChat.*` wire contract, the snapshot and change models, the `AgentChatThread` reducer, the timeline projection and `RuntimeAgentChatRepository` over an `AgentChatTransport`. See its [readme](../packages/alera_agent_chat/readme.md).
- `lib/src/features/agent_chat/infra`: `RuntimeHostAgentChatTransport` adapts the desktop runtime client, mapping host errors to package exceptions and the socket's connect/disconnect events to the package lifecycle events.
- `lib/src/features/agent_chat/application`: `AgentChatController` (one per open chat) reads the snapshot after subscribing to changes, applies changes by cursor, reloads on a skipped cursor, a misaligned text append or a reconnect, and keeps itself alive while a send or a response is in flight. Composer drafts persist locally in desktop SQLite and phone preferences, scoped by host, workspace and chat. Hydration cannot overwrite newer edits. Unanswered submissions retain their original IDs and are restored separately from later composer text.
- `lib/src/features/agent_chat/presentation`: the tab surface, timeline, docks, composer, direct chat entry and archived-chat picker.
- `mobile/lib/src/features/agent_chat`: phone controllers and presentation over the same package, with `MobileAgentChatTransport` adapting the direct or relay runtime connection. The phone never starts a provider process.

The runtime side is described in `rust/alera-cli/src/terminal_host/server/agent_chat_runtime/readme.md`; chat orchestration in [agent-chat-orchestration.md](agent-chat-orchestration.md).

Human CLI/MCP controls, independent capability gates, host Settings, explicit model resets, and retry identities are described in [Agent Chat CLI And MCP](agent-chat-cli.md). The `alera agent-chat` group is distinct from lineage-bound `alera chat` orchestration; Settings tools do not enter the injected agent catalog.

## Workbench integration

- Tab kind `agentChat` with host-owned payload `{chatId, provider, providerInstanceId, model?}`; `agentChatId` is read as a legacy alias. The app declares `supportedTabKinds: ["agentChat"]` in its hello, so older apps never receive these tabs.
- "Agent Chat" in a pane's add-tab menu, the Agent Chat card of an empty side panel, and the New Agent Chat shortcut (`Mod+Shift+T`) open a composer directly. Provider startup is deferred until the first send. The selected provider and model can be changed in the composer; when no enabled provider is available, the draft remains unselected and offers Provider Settings. Creating or reusing a draft focuses it only while the person is still on that workspace.
- Closing a chat that has never sent a message discards its record and tab atomically; otherwise it archives the chat and stops its provider while retaining history. The host guards close/send races. A deletion event lets another client retain its local unsent text. Archived Chats is a separate entry, and Reopen brings a retained chat back in a tab.
- A chat tab shows the status dot colors agent terminals use (working, waiting for the person, failed) even while the chat is not open. The dots come from `agentChat.list` statuses kept current by each chat's session and request changes, not from terminal agent presence.
- Every entry point checks `agentChatV1`. Against an older runtime the menu entry is hidden, the shortcut explains that an update is required, and an existing chat tab shows Update Required. There is no fallback.

## Conversation

- Each turn shows the prompt, compact live work, a "Worked for" divider, then the answer. Commands, edits, tool calls and reasoning expand for details; failed or interrupted work stays visible. Scroll position and disclosure state are kept per chat, with an explicit Jump To Latest action when the reader leaves the live edge.
- Approvals, questions and supported elicitation forms share a request dock above the composer. It offers exactly the runtime's decisions, pages through pending requests and retains drafts per request. Focus changes respect recent typing rather than interrupting the composer.
- Input that another chat or an orchestration wake sent renders as a notice rather than as the person's message, and never navigates anywhere.
- Desktop agent Markdown is rendered without fetching images; `http`, `https` and `mailto` links leave the app. Mobile uses the workspace Markdown viewer's remote-image URI policy and opens `http` and `https` links in the browser. Bare file paths open as workspace files on both surfaces.

Long text, reasoning and tool output are stored in bounded continuation rows. The shared timeline joins contiguous rows per stream while preserving the original item IDs used by synchronization. A history page with missing rows shows selectable partial text and a notice; loading the remaining history restores the complete message and its Markdown rendering. Automated partial prompts stay notices and do not enter prompt history.

Large native metadata keeps a redacted preview on its visible item and stores the complete redacted JSON in linked hidden rows. Hidden rows do not appear in normal snapshots, history or timeline changes. Load Full Data fetches that text explicitly through the paged `agentChat.payload` endpoint, including archived chats. Loading checks chunk order and payload consistency before exposing a bounded selectable preview and Copy Full Data. Native JSON is not decoded or pretty-printed on the UI isolate; loading and retry states remain local to the details panel.

## Composer

- New chat entry shows a pending state while the host creates the draft and focuses its composer, including side panels. Moving to another field or surface during creation preserves that focus and selection.
- Enter sends; while a turn runs the runtime queues the message, or steers only when the adapter supports native steering. The queue dock supports cancellation, text editing without losing attachments, and promotion to steering with the exact active turn id. Failed or unsupported steering leaves the queued entry intact. Escape stops a running turn. Arrow keys in an empty composer recall earlier prompts the person sent.
- A sent message shows immediately and is replaced by the runtime's item carrying the same client message id. A failed send keeps its id, so Retry is deduplicated by the runtime; Edit returns the text to the composer.
- A searchable combined provider/model picker lives in the composer. Provider switches require an idle chat and preserve context. Choosing Provider Default explicitly clears the prior model. Approval mode, plan mode, verified model-specific reasoning effort and context usage stay alongside the picker. Plan mode is offered for Codex, Claude Code and Cursor; Claude switches its permission mode per turn and its `ExitPlanMode` plan appears as the proposed plan. Plan progress (the agent's task list) comes from Codex plan updates, Claude `TodoWrite`, Cursor, OpenCode todos and ACP plan updates. Full Access requires confirmation. The runtime rejects settings it cannot honor and explains the failure above the composer.
- Narrow composers shorten the provider-default label to Default and fold secondary controls into More Controls. Active Full Access and Plan remain visible as warning/mode indicators; model labels truncate with their complete value available in the tooltip.
- A dropped connection keeps the transcript readable, disables the composer and reloads the snapshot when the runtime returns. A stopped session offers the recovery actions the runtime verified (resume or start a new session); sending also resumes it.

## Providers and Models

Settings manages provider instances for the selected host, including enabled state, executable and arguments, environment overrides, custom models, defaults, hidden models and favorites. Sensitive environment and option values are write-only; responses expose only whether a secret is saved. Mutations use revisions and request receipts. Catalog status distinguishes installation, bounded discovery and verified sign-in evidence rather than treating an existing credential as proof of authentication.

New-chat selection resolves project defaults, the launching chat in the same workspace, an explicit default, remembered selection and finally the first enabled available instance. Preferences synchronize through the host. Paired phones can change preferences, model visibility, enabled state and secrets; launch definitions remain desktop administration. Verified installation and sign-in suppress redundant Install and Sign In actions. An ACP instance without an executable shows Setup Required rather than a launch error. Sign In, Install and Update use an opaque provider-instance/action request: the owning host selects its verified recipe and hydrates the instance environment before spawning a command terminal. Secrets and launch recipes are never typed by the client. A desktop can run these actions on a Remote Host when both runtimes advertise `agentChatRemoteProviderSetupV1`; older hosts retain the copy-only explanation. The phone retains copy-only setup. Remote setup output and input are restricted to admitted desktop clients, and the ephemeral terminal is closed with its dialog.

## Attachments and Attention Push

`agentChatAttachmentUploadV1` transfers selected local files to the chat's owning host through bounded, replayable chunks. Uploads are scoped to the authenticated human, workspace and chat. A completed upload returns an attachment receipt; send resolves that receipt on the owner instead of trusting a client path. Desktop transfers device-picked or pasted files before sending; workspace references remain owner-host paths and are never guessed from matching local files. Phones can upload photos and files directly through their paired hub to a remote chat owner. Unsupported remote uploads fail explicitly; older local hosts retain their existing path/upload flow.

Unanswered submissions retain completed attachment receipts and the same client message ID, so retry does not silently upload or execute a different prompt. Upload errors keep the submission available for Retry or Edit. Unused uploads expire; referenced files remain with their chat history. Device-local drafts are not synchronized between clients.

With runtime cloud push enabled and the phone subscribed to Attention, newly committed approval/question requests and Chat Tasks needing attention produce identifier-only notifications. Cursor replay, request/task overlap and cooldown repeats are damped; snapshots do not trigger notifications. Remote chat events use the hub's cloud account after owner validation. Tapping opens the matching chat or Activity task; arrival and foreground notices never navigate automatically. Tests use fake cloud delivery and do not prove FCM delivery to a real phone.

## History and File Checkpoints

Fork, transcript rewind, native conversation rewind, file rewind, approval history and turn diff are independent capability-gated operations. Transcript rewind restores the prompt and retained history without reverting files. Native conversation rewind requires an exact supported provider boundary from the current process; the host does not retry a count-based rollback as an approximation.

Claude File Checkpointing can be enabled while idle and takes effect on the next provider start. Rewind Files uses only a provider-observed user-message UUID. Provider acknowledgment and observed file effects are separate result fields; missing evidence is presented as unverified.

Native rewinds reserve a durable intent before provider I/O and finalize history and receipts atomically. An interrupted or ambiguous operation pauses mutations and exposes explicit reconciliation actions. Restart recovery never blindly repeats native I/O. Both clients preserve the draft while the operation is unresolved.

## Chat Tasks and Attention

Chats can send messages to existing chats or delegate work into an existing workspace, a shared workspace or an isolated worktree in another project. The task dock preserves parent/child context and keeps navigation explicit. Settled plans can open Implement In New Workspace using the same delegation form. Human callers can attach a parent chat; injected agents remain bound to host-validated lineage and generation credentials. Activity remains the common attention surface for Chat Tasks, Runs, Questions and Automations.

Read cursors are host-shared. Task and waiting-input notices do not change the selected workspace or tab. Native provider subagent metadata is retained separately from application-owned chat tasks.

## Known limits

- Uploads require the owning host's attachment capability; there is no remote path fallback for a device-local file.
- Reasoning effort is shown only for verified provider/model metadata; an adapter API alone does not fabricate available values.
- Unification with terminal orchestration remains a separate follow-up.
