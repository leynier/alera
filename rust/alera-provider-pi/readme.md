# Pi provider

This crate adapts Pi's `pi --mode rpc` newline-delimited JSON protocol to the shared Rust provider contract. It uses the common bounded JSON transport and accepts an injected transport for deterministic tests.

The process inherits Pi's normal extensions, skills, `AGENTS.md`, `SYSTEM.md`, settings and auth environment. The adapter does not disable or replace those user-owned configuration sources.

Pi has no SDK dependency in this integration. The provider keeps `agent_settled` as the only terminal turn signal, correlates RPC responses separately from extension UI requests, and preserves complete native records in raw events.

Lifecycle commands are newline-delimited JSON records: `get_state`, optional `switch_session` with `sessionPath` for resume, `set_model` with a `provider/model` split, `prompt`, and `abort`. A new process supplies the current session returned by `get_state`; the adapter does not replace it with another session. A prompt is fire-and-forget and its acknowledgement is an id-less `response`; correlated commands use a typed string or integer `id` and a boolean `success` field. After `agent_settled`, the adapter probes `get_state` and emits the terminal event only when streaming, compaction, and pending message work have all stopped.

Extension `confirm`, `select`, `input`, and `editor` requests retain their native id and full record. Responses use the native wire shape with top-level `confirmed`, `value`, or `cancelled` fields. The adapter always injects its permission extension, including when no MCP servers are configured. Its public `tool_call` hook enforces approval-required/on-request behavior before tool execution. Only verified Pi built-in read, grep, find, ls, and tool-search tools bypass confirmation. Other built-in tools and all extension/MCP tools require explicit approval; decline, cancellation, timeout, unavailable UI, and shutdown block the call. External tool names and read-only annotations cannot grant a bypass. Other runtime modes, approval policies, and sandbox policies remain unsupported.

## mcp bridge

Pi does not provide an MCP boundary in its RPC protocol, so this crate ships a small extension asset that uses Pi's public `registerTool` API. Configure `PiProviderConfig::mcp_servers` before `PiProvider::spawn`; each stdio server is serialized into a private file and the process receives `--extension` plus that file path. `SessionStartInput::mcp_servers` is host-owned metadata and, when present, must match the launch configuration because extensions are loaded before a session starts.

The extension starts each configured command with Node's `spawn`, performs the MCP `initialize` and `notifications/initialized` handshake, collects every tools/list page, and exposes them as `chat_<server>_<tool>` tools. Tool collection rejects duplicate names, invalid/repeated cursors, more than 256 pages, and more than 10,000 tools before publishing any tool. Calls use correlated JSON-RPC ids, preserve typed ids, reject protocol errors, propagate abort signals with `notifications/cancelled`, and bound request/write deadlines. A failed server is reported through Pi's session warning hook and contributes no advertised tools.

Pi's awaited `session_shutdown` hook closes all owned servers, including startup in progress, aborts approval dialogs, rejects pending requests/writes, waits for pipe readers to close, and removes its exit listener. Each server runs behind a small stdio supervisor with a private IPC channel to Pi. The supervisor forwards stdio with stream backpressure and retains the real server exit status. Unix supervisors own a detached process group with their server and descendants: shutdown sends SIGTERM, escalates the group to SIGKILL after 500 ms, and waits up to one second to reap the direct supervisor. If Pi is killed abruptly, its IPC channel disconnects and the still-running supervisor immediately kills its own group. This covers provider Drop without PID registries or relying on Pi exit hooks. Windows uses `windowsHide: true` for the supervisor, server, and `taskkill /T /F`, with a one-second deadline. Node owns this external-server boundary, so these spawn settings provide the equivalent window suppression outside the Rust process helpers. The synchronous process exit fallback immediately forces tree termination; it does not depend on timers running after exit. Private extension assets and the spec file remain owned by the Rust provider lease and are deleted when that lease is dropped.

Node and normal Bun launches reuse `process.execPath` for the supervisor. A compiled Pi Bun executable cannot interpret another JavaScript file, so that form uses `node` from the inherited host PATH, or the host-configured `ALERA_PI_MCP_JS_RUNTIME` executable path (Node or Bun). A missing runtime reports the server as unavailable; it never removes the permission gate.

Only stdio injection is supported. HTTP servers are rejected at launch/session validation and `capabilities().mcp_injection.http` is false. Credential values remain in the private spec file used by the extension; command arguments and Pi events contain the file path rather than the values.

The bridge follows the extension API and MCP framing used by `reference_projects/t3code/packages/provider-pi/src/server/mcpExtensionSource.ts`; the Rust adapter does not bundle a Pi executable or an MCP server implementation.

Run the deterministic Node regressions with `node --test rust/alera-provider-pi/tests/mcp_extension.test.mjs`. Set `ALERA_PI_EXTENSION_LOADER` to an installed Pi `dist/core/extensions/loader.js` path to additionally validate its public factory loader and a real built-in write tool without model inference. Set `ALERA_PI_CLI` to its `dist/cli.js` path to verify abrupt SIGKILL cleanup through a real, isolated Pi RPC process; no prompt or model call is sent. Set `ALERA_PI_BUN_RUNTIME` to a Bun executable to verify Bun IPC and a temporary compiled Bun host. The local verification used Pi 1.2.0 and Bun 1.4.3. Windows process-tree behavior is implemented but requires validation on Windows.

## upstream provenance

This crate implements the public Pi RPC boundary used by the pinned reference checkout. It does not copy a Pi SDK and does not redistribute the Pi executable.

- Reference source: `reference_projects/t3code`
- Reference revision: `5d6e4192bfcf9eca09741605e12c72b5970025e4`
- Adapter: `packages/provider-pi/src/server/adapter.ts`
- RPC transport: `packages/provider-pi/src/server/rpc.ts`
- Launch command: `pi --mode rpc`

The upstream reference is MIT licensed. This crate retains its own MIT notice in `LICENSE-MIT`. Pi's executable, extensions, user settings and auth remain external runtime dependencies and are not bundled here.
