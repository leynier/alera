# Rust Agent Providers

The Rust workspace contains a UI-independent provider protocol, a shared process transport, adapters for Codex and Claude Code, and a Rust port of Claude's provider-facing Python SDK. These crates are not connected to Flutter, the terminal host, or production agent sessions. The native app and sidecar do not depend on them.

## Source References

- T3 Code: [`reference_projects/t3code`](../reference_projects/t3code), commit `5d6e4192bfcf9eca09741605e12c72b5970025e4`. The contract follows `packages/contracts/src/providerRuntime.ts`, `providerPolicy.ts`, and the provider lifecycle in `packages/provider-core/src/server/ProviderAdapter.ts`.
- Claude Python SDK: [`reference_projects/claude-agent-sdk-python`](../reference_projects/claude-agent-sdk-python), commit `b6e9d12fe1cc98dde988ab7b7713c1feeee50c6c`. This is the official `anthropics/claude-agent-sdk-python` repository, SDK version `0.2.165`. The port preserves Anthropic's MIT notice in [`rust/claude-agent-sdk/LICENSE`](../rust/claude-agent-sdk/LICENSE).
- Codex wire protocol: [Codex App Server](https://learn.chatgpt.com/docs/app-server). The pinned T3 reference includes its generated app-server schemas and adapter fixtures.

Both reference projects are development inputs only. No crate imports code or loads assets from a reference submodule at runtime. The protocol crate preserves T3's MIT notice in `LICENSE-T3`.

## Crates

| Crate | Responsibility |
| --- | --- |
| `alera-agent-transport` | Injectable `JsonTransport`, bounded NDJSON subprocess transport, process cleanup, and scripted mocks. |
| `alera-provider-protocol` | Shared provider lifecycle, session and turn inputs, capabilities, policies, approvals, questions, normalized runtime events, and validation. |
| `alera-provider-codex` | Codex app-server requests, response correlation, server requests, and native-to-shared event mapping. |
| `claude-agent-sdk` | Rust implementation of Claude Code's stream-json SDK client, options, messages, controls, permissions, hooks, and MCP callbacks. |
| `alera-provider-claude` | Claude SDK session and turn lifecycle, request callbacks, and native-to-shared event mapping. |

The SDK and adapters depend on the shared transport. The Claude adapter uses the Rust SDK directly and requires no Python interpreter. The transport hydrates the environment through `alera-core::login_shell_environment`, shared with the terminal host through its existing module reexports. Login-shell PATH makes CLIs installed under Homebrew and version-manager prefixes available to GUI launches. Explicit per-call environment overrides take precedence, including PATH; Windows keeps its inherited environment. Hydrated values remain in memory.

## Shared Contract

`Provider` exposes initialization, session start or resume, turn submission, interruption, request responses, event consumption, and closure. Each adapter reports the operations it implements through `ProviderCapabilities`. Unsupported features must return an explicit error. The shared interface does not implement T3's persistence, orchestration scheduler, provider switching, or UI projections.

Caller-owned `threadId` stays separate from the provider's `nativeThreadId`. Events carry `providerRefs` for native turn, item, and request identities. Claude's local turn IDs are synthetic because its SDK does not expose Codex-style native turn IDs. `RequestId` preserves the native JSON string or integer used for response correlation.

This standalone boundary does not allocate T3 orchestration V2 app-owned turn, item, or request IDs. Codex envelopes use its native identities, while Claude uses local synthetic turns and callback identities. Before connecting these crates to an orchestration V2 store or UI, add an application identity allocator and mapping layer that rewrites those envelope fields while retaining `providerRefs`. The events are a normalized provider boundary, not a drop-in replacement for T3's persisted V2 domain records.

Event names and policy values use T3's wire vocabulary, including `content.delta`, `turn.completed`, `request.opened`, and `user-input.requested`. Core envelopes and payloads can be checked with `ProviderEvent::validate`. Event payloads remain JSON so provider extensions and evolving schemas are retained. Unknown event names round-trip through `EventKind::Unknown`; the original provider frame remains available in `raw`.

Input validation follows the reference limits of 120,000 UTF-16 code units and 100 attachments per turn. An attachment-only turn is valid. Runtime policy defaults to approval-required in this library; callers explicitly select greater access. Capability flags describe implemented adapter operations, rather than everything the underlying CLI may support.

## Requests And Events

Consumers can inspect `runtime_request` and call `Provider::respond`, or use `next_event_with` with a `RequestHandler`. Responses must keep the exact native request ID. The callback wrapper rejects an answer for a different request.

Codex initializes its bidirectional app-server connection once, awaits the response, and sends `initialized` before any thread or turn request. Messages omit the `jsonrpc` field and use newline-delimited JSON. Acknowledging `turn/interrupt` does not complete the turn; only the subsequent terminal notification establishes its outcome. `turn/completed` may indicate success, interruption, or failure.

Codex tool questions use the generated schema's question-keyed answer object, where each answer contains an `answers` array. MCP elicitation uses an `action` plus nullable `content`. Claude tool permission replies use the SDK's `behavior`, `updatedInput`, and `updatedPermissions` fields. The adapters preserve provider messages alongside their normalized events.

Claude's `result` ends one response, not the SDK connection. The SDK stays available for subsequent turns, controls, and task notifications until explicitly closed. Permission, hook, and MCP callbacks share the control channel and must not stop that channel from processing responses.

## SDK Port Scope

The Rust SDK ports the provider-facing stream-json and bidirectional control layer: client connection, prompt submission, message streaming, initialization, permissions, hooks, MCP message callbacks, interrupt, model and permission-mode changes, file rewind, MCP reconnect/toggle/status, context usage, and task stopping. Its typed messages retain their original JSON, including unknown message and content-block variants.

Python session-store backends, transcript mirroring, filesystem session management, Python MCP server objects, AnyIO integration, and Python-specific plugin construction are outside this provider-facing port. The CLI remains an independently installed executable. This crate does not bundle or reimplement Claude Code itself. See the SDK's `README.md` and `UPSTREAM.md` for its public API and source provenance.

## Validation

Run from `rust/` so rustup selects the pinned Rust toolchain:

```sh
cargo fmt --all -- --check
cargo test --locked -p alera-agent-transport -p alera-provider-protocol -p claude-agent-sdk -p alera-provider-codex -p alera-provider-claude
cargo clippy --locked -p alera-agent-transport -p alera-provider-protocol -p claude-agent-sdk -p alera-provider-codex -p alera-provider-claude --all-targets -- -D warnings
```

Tests use scripted native frames and local Rust fixture processes. They verify serialization and validation, initialization ordering, request correlation, event normalization, approval and question responses, controls, framing limits, failure paths, and subprocess cleanup. They do not make model requests or require account credentials. Passing them proves the tested protocol behavior and local transport behavior; live CLI/account compatibility remains a separate check.
