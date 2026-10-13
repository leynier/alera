# Claude Agent SDK provenance

This crate is a Rust port of the provider-facing stream-json and control protocol from Anthropic's MIT-licensed Python SDK.

- Upstream: https://github.com/anthropics/claude-agent-sdk-python
- Pinned source commit: `b6e9d12fe1cc98dde988ab7b7713c1feeee50c6c`
- Source snapshot date: 2026-10-09
- Upstream package version: `0.2.165`
- Bundled Claude Code CLI version in that snapshot: `2.1.296`
- License: MIT, Copyright (c) 2025 Anthropic, PBC

Only the public provider protocol needed by Alera is ported here. The Python runtime, AnyIO implementation, MCP Python server adapters, session-store backends, transcript mirroring, plugin helpers, and Python-only task compatibility helpers are not copied. `ClaudeAgentOptions::validate` rejects the currently unrepresentable stderr callback and non-`json_schema` output format; session stores, transcript mirrors, plugin APIs, and Python MCP server objects have no Rust API in this crate.
