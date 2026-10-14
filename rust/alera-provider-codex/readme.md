# provider adapter scope

This crate maps the shared provider contract to the app-server JSONL boundary. Host-owned MCP servers are projected into `thread/start` and `thread/resume` under `config.mcp_servers`: stdio uses `command`, `args`, and `env`, while HTTP uses `url` and `http_headers`.

Injected server names cannot replace caller-owned entries. The native boundary does not represent a stdio working directory, so a spec that supplies one is rejected before a native request is sent. Secret environment values and headers are passed to the native process but are not copied into provider events or debug output.

The MCP projection is covered by transport-backed lifecycle tests for new and resumed threads, collisions, and unsupported fields.

Native steering calls `turn/steer` with `expectedTurnId`, validates the acknowledgement, and keeps the existing turn identity. Steering cannot alter active turn settings. Fork starts a new connection session through `thread/fork`; `NativeForkBoundary::Turn` maps to inclusive `lastTurnId`. Legacy count rollback uses `thread/rollback` with `numTurns`; advertised paginated history instead requires `NativeRollbackBoundary::BeforeTurn`, mapped to `thread/revert` with `beforeTurnId`. Neither operation restores working files.

Canonical `reasoningEffort` maps to thread `config.model_reasoning_effort`, turn `effort`, and Plan `collaborationMode.settings.reasoning_effort`. Per-model values must come from native model discovery. Collaboration-tool and child-thread lineage preserve native references; known child terminal events become task events and cannot terminate the parent's turn. Wire fixtures cover steering preconditions, acknowledgements, RPC request-id collisions/errors, native history boundaries, effort mapping, and child isolation.
