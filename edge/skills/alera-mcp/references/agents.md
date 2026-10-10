# Agents, Tabs, And Terminals

## Launching Agents

`list_agent_profiles` lists the agent profiles the user declared (Claude, Codex, and others) with their ids and names. Pick a profile from that list; never invent one. Profile administration belongs to the `alera-mcp-agent-profiles` skill.

`launch_agent` opens a new tab in an existing workspace. Send a `prompt` to start a conversation, `resumeSessionId` to continue an earlier one, or neither to start the agent idle. Pass `clientRequestId` so a retry does not open a second tab.

## Tabs

`list_tabs` lists a workspace's tabs, including terminal and agent tabs.

- `create_tab` opens a terminal tab, optionally running a command.
- `rename_tab` renames one, and `generate_tab_title` names an agent tab from its conversation with AI Assist.
- `close_tab` closes a tab and ends its session.
- `link_agent_to_tab` binds a running agent conversation to a tab again when the tab stopped showing the agent's status.

## Terminals

`list_terminals` lists live sessions with their handles. Most terminal tools take a `handle` from it. `show_terminal` shows one session with its agent and lifecycle state.

- `read_terminal` reads retained output. Pass the returned cursor next time to read only what is new.
- `wait_for_terminal` waits for `process-started`, `agent-detected`, `agent-ready`, or `dispatch-accepted`.
- `write_terminal` types text. Use `submit` to send a prompt to an interactive agent; use `enter` to press Enter after a shell command. Type into an agent only when the user asked for it, and read the terminal first so you do not interrupt work in progress.
- `restart_terminal` replaces the process and keeps the tab and scrollback. `terminate_terminal` ends the session and closes the tab.
- `prune_terminals` lists stopped terminal tabs, and with `apply` removes them. Run it without `apply` first.
- Pulse types a configured input into a terminal after workspace files change. `get_terminal_pulse` shows it, and `configure_terminal_pulse` changes, arms, or disarms it.

## Asking An Agent

The inbox lets you ask a running agent a question and read its answer later. The agent sees which MCP client asked; it cannot read this conversation, so put everything it needs in the question.

1. `list_inbox_targets` lists the agents you can reach.
2. `ask_agent` asks by terminal `to`, or by `workspaceId` when the workspace runs one agent (add `agent` to choose among several). It returns the question id and thread id. Pass `threadId` to follow up in the same thread.
3. `wait_for_reply` waits for news about one question. `wait_for_inbox` waits for any reply to this client's questions, so one call covers every open question. Pass the returned cursor as `after`.

A question reaches the agent when its current turn ends. `expiresIn` drops it if it is never delivered. `cancel_question` cancels it only before the agent sees it.

- `list_inbox_threads` lists threads asked by every MCP client sharing this inbox; `isOwn` marks this client's. `show_inbox_thread` shows one thread whole.
- `mark_thread_read` marks a thread's replies as read for everyone sharing the inbox.
- `list_inboxes` lists the external inboxes with their counts.
- `list_agent_conversations` and `show_agent_conversation` show conversations between agents, read-only.
- `purge_inbox` deletes every question of the shared MCP inbox, including other clients' threads. Use it only when the user asks for exactly that.
