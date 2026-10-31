# Muse provider

This crate maps the public Muse Session Protocol into the shared provider contract. It uses the Rust `muse-agent-sdk` client over the bounded shared JSON transport and keeps the external `muse serve` executable as a configurable runtime dependency.

Runtime modes select both the MSP approval mode and a permission profile: approval-required uses `promptUnmatched` with `:ask-me`, auto uses `promptUnmatched` with `:auto-review`, where Muse's reviewer decides eligible approvals, and full access uses `allowAll` with `:unrestricted`. Selecting the profile explicitly keeps Muse's default from handing a supervised session's approvals to its reviewer. `session/resume` does not admit an approval mode, so a resumed session selects it with `session/setApprovalMode`; the profile is sent on resume too, but a host that admits it only on start keeps the session's earlier profile.

MCP injection is advertised only while an initialized connection has granted `sessionMcp`. Injected stdio and streamable HTTP servers use required startup mode for both session creation and resume, so the host must report connection failures instead of silently dropping orchestration tools. Stdio MCP `cwd` remains unsupported by the native MSP schema and is rejected before session startup.

The implementation follows `@muse-code/sdk` 1.4.6 from `meta-models/muse-code-sdk` at commit `ea88c8221d381de7cb28281be8bc6b8b1507ba72`. The upstream SDK and committed protocol declarations are MIT licensed; this crate retains the accompanying MIT notice in `LICENSE-MIT`. The external host executable is not included in the upstream source repository or package and has separate licensing.
