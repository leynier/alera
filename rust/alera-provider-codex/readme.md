# provider adapter scope

This crate maps the shared provider contract to the app-server JSONL boundary. Host-owned MCP servers are projected into `thread/start` and `thread/resume` under `config.mcp_servers`: stdio uses `command`, `args`, and `env`, while HTTP uses `url` and `http_headers`.

Injected server names cannot replace caller-owned entries. The native boundary does not represent a stdio working directory, so a spec that supplies one is rejected before a native request is sent. Secret environment values and headers are passed to the native process but are not copied into provider events or debug output.

The MCP projection is covered by transport-backed lifecycle tests for new and resumed threads, collisions, and unsupported fields.
