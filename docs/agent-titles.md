# Agent Titles

AI Assist names new agent conversations automatically in terminal tabs. Desktop and mobile share the title persisted by the runtime. Configure the provider, model, and instructions under **Settings > AI Assist > Agent Titles**. **Auto-Generate Agent Titles** defaults on and follows the main AI Assist switch; turning it off retains existing titles and leaves manual generation available while AI Assist itself remains enabled.

The initial title uses the first user prompt. Profile launches capture that prompt before adding profile or project instructions. Hooks supply prompts for agents launched directly in a terminal. When the prompt is unavailable, a short deferred job uses recent terminal output. Internal generation runs in a separate temporary directory without the originating terminal's hook identity.

Use **Generate Title** or **Regenerate Title** in the tab menu on desktop or mobile. The same generate action is also available from the agent-run rows under a workspace in the desktop sidebar. Regeneration combines the retained initial prompt with recent context and applies a valid result directly. Context is limited to 16 KiB; terminal control sequences and adjacent duplicate redraw lines are removed. Empty context or an invalid result leaves the old name intact. A title is at most 80 characters; the generation prompt requests 3 to 7 words in the task's language.

**Show Tab Titles in Sidebar** (Settings > Agents > Behavior, portable through Configuration Sync) replaces the latest activity text in those sidebar rows with each tab's persisted title. Turn it off to keep the current tool or assistant snippet.

Manual names take precedence over automatic generation, including when a new conversation starts in the same tab. An explicit regeneration may replace a manual name, but a rename made while that job runs wins. Closing the tab or switching conversations invalidates pending results. Multiple clients cannot start simultaneous jobs for the same tab.

## Conversation detection

Conversation identity is separate from agent activity. Turn completion, another user prompt, reconnection, and idle time do not themselves identify a new conversation. The runtime accepts native conversation, session, or thread identifiers from hooks; OpenCode plugins forward their session identifiers, Pi forwards its session-manager identifier, and Amp already forwards its thread identifier. Hooks explicitly identifying a parent session are ignored for titles so they cannot rename that parent tab. Managed OpenCode plugins resolve session ancestry with a bounded read-only SDK lookup and forward parent identity. If ancestry is unavailable, the event still updates activity but is excluded from title tracking. Other integrations that omit parent identity cannot provide that distinction.

A session-start event can explicitly resume a previously visited native identity; ordinary delayed hooks cannot. Resuming cancels the previous conversation's pending job and never repeats an automatic attempt. The runtime retains only the last 16 conversations' bounded first prompts for this purpose. Older resumes use current terminal context for manual regeneration, without borrowing another conversation's prompt.

When an integration supplies no reliable identity, Alera generates the initial title for a new eligible tab but does not guess subsequent conversation changes. Manual regeneration remains available. Hook availability and identifiers depend on the installed CLI; status-only integrations therefore use this conservative behavior. Disabling an agent's hooks is not overridden by enabling title generation.

Existing conversations without title metadata are baselined, not renamed automatically. New conversations confirmed afterwards become eligible. An automatic attempt is persisted once per eligible conversation, so failures and runtime restarts do not repeatedly consume provider quota. Failed generations can be retried manually.

## Runtime contract

`aiText.agentTitle.generate` accepts `tabId`, `expectedConversationId`, and `expectedRevision`, including explicit null preconditions for tabs predating this feature. The runtime reads the context, resolves the shared `agentTitle` AI Assist operation, validates the current identity and title revision, and returns the applied `title`. New clients expose the action only when `aiTextAgentTitleV1` is advertised. The capability is present in both desktop discovery and `mobile.hello`; neither strict protocol version changes.

The initial prompt and internal identity state are host-owned tab payload data and are removed from public projections. Public metadata contains an opaque conversation identifier, title revision, source, and generation status. Client tab updates cannot replace the host-owned state. Generated names also set the existing `manualTitle` display flag for older clients, while `agentTitleSource` distinguishes generation from a manual rename. Prompts and terminal context are not written to diagnostics.

## Validation

Runtime tests cover conversation boundaries, duplicate and late hooks, manual rename races, stale results, restart persistence, disabled settings, empty context, ANSI cleanup, private payloads, and authenticated protocol routing. A shell fixture exercises the background provider process, cancellation, timeout, temporary-directory cleanup, and removal of terminal hook identity without using credentials. The subprocess fixture runs on Unix; the pure state and protocol cases are platform independent.

Flutter tests cover settings serialization, request preconditions, title precedence, capability gating, disabled progress actions, and manual error feedback. The OpenCode ancestry lookup uses the documented [v1 SDK session API](https://opencode.ai/docs/sdk/) and [v2 plugin session API](https://opencode.ai/v2/docs/build/plugins/). Run the regular desktop and mobile analysis/tests and `make rust-test` for the Rust workspace. `node tool/testing/agent_title_hooks_smoke.mjs`, run from the repository root, exercises the actual Rust-managed and Dart-managed OpenCode, OpenCode 2, and Pi plugin sources with synthetic events and a fake hook receiver. It does not launch or authenticate those CLIs.

Before release, verify real CLI sessions on macOS, Windows, and Linux: submit a first prompt, submit another turn, start a new conversation in the same tab, resume a conversation, rename while generating, and regenerate from both desktop and the paired phone. For a CLI that does not emit a stable conversation identifier, expect only initial generation and manual regeneration until the integration gains a confirmed identity signal.
