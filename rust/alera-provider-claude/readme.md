# provider adapter scope

This crate maps the shared provider contract to the Rust client for the streaming CLI. Host-owned MCP servers are projected into the SDK `mcp_servers` map: stdio uses `type`, `command`, `args`, and `env`, while HTTP uses `type`, `url`, and `headers`.

Injected server names cannot replace caller-owned entries. The native boundary does not represent a stdio working directory, so a spec that supplies one is rejected before launch. Only the trusted `alera` server receives the matching `mcp__alera__*` allowlist entry; other servers retain normal permission handling. Secret environment values and headers are not copied into provider events or debug output.

The projection is covered by lifecycle tests for exact native options, collisions, unsupported fields, and preservation of existing options.

Native fork uses the SDK's `resume`, `fork_session`, and optional `resume_session_at` on a fresh provider connection. `NativeForkBoundary::Message` is an inclusive native transcript UUID, retained as `payload.nativeMessageId` from full assistant messages; content/tool lifecycle ids are different references. A fork result does not claim a native id until Claude reports the new session identity. Generic conversation rollback and active turn steering remain unsupported.

`rewind_files` uses the SDK control request and requires `enableFileCheckpointing: true` at session launch. It restores checkpointed files only, without truncating conversation history. Canonical `reasoningEffort` maps to the verified SDK `effort` launch option (`--effort`); changing effort per turn is unsupported. Upstream `xhigh` is honored only with explicitly selected Opus 4.7, because other models fall back to high. Native task notifications and terminal update patches retain their task/tool/session references; absent native task ids remain warnings.

`native_history_capabilities.fileCheckpointing` reports launch-option support, while `rewindFiles` is true only on a live session launched with checkpointing enabled. Launch also requests replayed user messages. The provider keeps an optional `TurnInput.options.appUserItemId` locally and projects `payload.nativeUserMessageId` only when the parsed user frame's exact raw UUID matches a live submitted main prompt, app item, native session, and turn. Historical, synthetic, tool-result, and mismatched frames cannot create checkpoint correlation; assistant UUIDs remain separate fork boundaries. The host updates the original user item rather than appending a replayed echo.

Native file rewind returns optional native `canRewind`, error, file statistics, skipped-link count, and raw response for internal reconciliation. An empty acknowledgement does not confirm file restoration; `canRewind: false` and native error fields remain explicit outcomes. Public host views must allowlist observations rather than exposing raw provider responses.
