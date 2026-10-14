# Claude Agent SDK for Rust

This crate ports the provider-facing stream-json and bidirectional control protocol from Anthropic's MIT-licensed Python SDK at commit `b6e9d12fe1cc98dde988ab7b7713c1feeee50c6c`. It runs Claude Code through the shared `alera-agent-transport` crate, so subprocess lifecycle, line framing, frame limits, and platform-safe spawning stay behind one injectable transport boundary.

```rust,no_run
use claude_agent_sdk::{ClaudeAgentOptions, ClaudeClient};

# async fn example() -> claude_agent_sdk::Result<()> {
let client = ClaudeClient::connect(ClaudeAgentOptions::default()).await?;
client.send_prompt("Summarize the repository").await?;
while let Some(message) = client.next_message().await? {
    if message.is_terminal_result() { break; }
}
client.close().await?;
# Ok(())
# }
```

The port covers typed stream messages, the provider CLI options that map to command-line or initialize fields, initialize negotiation, user prompts, control request routing, permission and hook callbacks, MCP callback messages, interrupts, model and permission-mode changes, file rewind, MCP status/toggle/reconnect, context usage, task stopping, injectable transports, bounded timeouts, and lifecycle cleanup.

`ClaudeClient::rewind_files` returns `RewindFilesResult` with optional native outcome fields and the original response. The camelCase response contract is verified against Anthropic's published `@anthropic-ai/claude-agent-sdk` 0.3.276 `sdk.d.ts` and `sdk.mjs`, the version in the T3 reference lockfile: `canRewind`, `error`, `filesChanged`, `insertions`, `deletions`, and `skippedLinks`. Empty acknowledgements remain unknown, and malformed typed fields are errors. A dropped wait does not prove whether files changed; a late acknowledgement retains its original request id and cannot answer a subsequent request.

File checkpoint launch sets `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING=true`, matching the checked Python upstream. The adapter enables `--replay-user-messages` to receive checkpoint UUIDs. See the [official checkpoint documentation](https://code.claude.com/docs/en/agent-sdk/file-checkpointing); file rewind does not alter conversation history.

Incoming permission callbacks expose the native request id and full envelope through `ToolPermissionContext.control`; `McpCallbackWithContext` provides the same metadata for MCP callbacks while the two-argument `McpCallback` remains available.

`Query::collect` closes a one-shot stream after a result when no delegated task or non-idle session state remains; otherwise it keeps the control channel open for follow-up turns and waits for `session_state_changed: idle` or tracked task completion. `ClaudeAgentOptions::run_end_timeout` bounds that between-turn grace period and defaults to 10 minutes, matching the upstream CLI ceiling.

The port does not implement Python session-store materialization or transcript mirroring, Python MCP server objects such as `create_sdk_mcp_server`, plugin marketplace or local plugin helpers, the Python AnyIO runtime, stderr callbacks, or non-`json_schema` output formats. Those surfaces are either absent from `ClaudeAgentOptions` or rejected by `validate()` with an explicit error; they are not silently ignored.

# Claude Agent SDK provenance

This crate is a Rust port of the provider-facing stream-json and control protocol from Anthropic's MIT-licensed Python SDK.

- Upstream: https://github.com/anthropics/claude-agent-sdk-python
- Pinned source commit: `b6e9d12fe1cc98dde988ab7b7713c1feeee50c6c`
- Source snapshot date: 2026-10-09
- Upstream package version: `0.2.165`
- Bundled Claude Code CLI version in that snapshot: `2.1.296`
- License: MIT, Copyright (c) 2025 Anthropic, PBC

Only the public provider protocol needed by Alera is ported here. The Python runtime, AnyIO implementation, MCP Python server adapters, session-store backends, transcript mirroring, plugin helpers, and Python-only task compatibility helpers are not copied. `ClaudeAgentOptions::validate` rejects the currently unrepresentable stderr callback and non-`json_schema` output format; session stores, transcript mirrors, plugin APIs, and Python MCP server objects have no Rust API in this crate.
