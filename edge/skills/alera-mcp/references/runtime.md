# Runtime

## Status

- `runtime_status` shows whether the runtime host is running, its database, and its active sessions.
- `get_version` shows the Alera versions and the protocol and skill contract versions. Check it when a tool answers `capability_missing`; the runtime may need an Alera update.
- `get_resource_snapshot` shows CPU and memory use of the host, the runtime, and each terminal.

## Settings

`get_runtime_settings` shows the settings open to MCP clients. They include the default agent profile, the worktree folder, removal confirmations, AI Assist, and automation retention. `update_runtime_settings` changes them. It needs administrative access, and fields left out keep their values. Change settings only when the user asks.

Status hooks let agents report their state to Alera. `get_agent_integrations` shows them, and `set_agent_integrations` turns them on or off.

## Agent Quotas

`get_agent_quotas` shows usage limits for the enabled providers; `refresh` fetches new numbers.
- `refresh_claude_quota` reads one Claude account's usage again.
- `consume_codex_reset_credit` spends an offered Codex reset credit. It needs administrative access and the user's explicit request.

## Voice

`voice_status` shows the voice home agent and its speech pipeline. `voice_speak` says a short message to the user through it.

## Skills For Coding Agents

Coding agents that run in Alera terminals use their own Alera skills, installed on the runtime's machine. These are separate from the skills this server serves.
- `check_agent_skills` shows whether those skills are installed and whether they match the runtime's version. It also shows an install in progress (`install.running`) and the last finished one (`install.last`).
- `install_agent_skills` installs or updates them at the runtime's own version. It needs administrative access.
- The runtime runs the install as a job, and only one at a time. The call waits up to 45 seconds. State `running` means the install is still going: read `check_agent_skills` later rather than calling again.

Suggest an install when a skill is missing or outdated and agents misuse the `alera` CLI.
