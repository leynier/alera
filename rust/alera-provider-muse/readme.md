# Muse provider

This crate maps the public Muse Session Protocol into the shared provider contract. It uses the Rust `muse-agent-sdk` client over the bounded shared JSON transport and keeps the external `muse serve` executable as a configurable runtime dependency.

MCP injection is advertised only while an initialized connection has granted `sessionMcp`. Injected stdio and streamable HTTP servers use required startup mode for both session creation and resume, so the host must report connection failures instead of silently dropping orchestration tools. Stdio MCP `cwd` remains unsupported by the native MSP schema and is rejected before session startup.

The implementation follows `@muse-code/sdk` 1.4.6 from `meta-models/muse-code-sdk` at commit `ea88c8221d381de7cb28281be8bc6b8b1507ba72`. The upstream SDK and committed protocol declarations are MIT licensed; this crate retains the accompanying MIT notice in `LICENSE-MIT`. The external host executable is not included in the upstream source repository or package and has separate licensing.
