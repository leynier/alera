# provider adapter scope

This crate maps the shared provider contract to the Rust client for the streaming CLI. Host-owned MCP servers are projected into the SDK `mcp_servers` map: stdio uses `type`, `command`, `args`, and `env`, while HTTP uses `type`, `url`, and `headers`.

Injected server names cannot replace caller-owned entries. The native boundary does not represent a stdio working directory, so a spec that supplies one is rejected before launch. Only the trusted `alera` server receives the matching `mcp__alera__*` allowlist entry; other servers retain normal permission handling. Secret environment values and headers are not copied into provider events or debug output.

The projection is covered by lifecycle tests for exact native options, collisions, unsupported fields, and preservation of existing options.
