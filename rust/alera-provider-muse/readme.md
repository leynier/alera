# Muse provider

This crate maps the public Muse Session Protocol into the shared provider contract. It uses the Rust `muse-agent-sdk` client over the bounded shared JSON transport and keeps the external `muse serve` executable as a configurable runtime dependency.

Runtime modes select both the MSP approval mode and a permission profile: approval-required uses `promptUnmatched` with `:ask-me`, auto uses `promptUnmatched` with `:auto-review`, where Muse's reviewer decides eligible approvals, and full access uses `allowAll` with `:unrestricted`. Selecting the profile explicitly keeps Muse's default from handing a supervised session's approvals to its reviewer. `session/resume` does not admit an approval mode, so a resumed session selects it with `session/setApprovalMode`; the profile is sent on resume too, but a host that admits it only on start keeps the session's earlier profile.

Muse does not extend a full-access session's `allowAll` to workflow children, so the adapter approves a child's request (one carrying `subagentOrigin`) once on its behalf without showing it. Only the subject kinds MSP defines (`shell`, `fileAccess`, `network`, `unixSocket`, `process` and `tool`) qualify; an unknown kind, or an approval Muse refuses to settle that way, still reaches the person, as does every child approval in the other runtime modes.

The session's `workspaceRoot` is the chat directory's canonical path, with symlinks resolved and the disk's own case, because Muse rejects a root whose case differs from the disk's. On Windows that is the verbatim `\\?\` form Muse requires, while `muse serve` itself still starts in the plain directory. A directory that cannot be resolved is sent as given, in verbatim form on Windows.

A failed turn carries a `failureClass`: `usage_limit` when Muse types the stop as a used-up subscription quota (`error.quota`), and `unknown` otherwise. The class never comes from the error message, so a quota refusal a proxy relays as plain text stays `unknown`.

Turns send GIF, JPEG, PNG and WebP images, from local files or base64 data URLs, as native `image` parts. Every local attachment, including other image types and files such as PDFs, is also named by path in the prompt (`[Attached file is saved at: …]`), so the agent can open it and none is silently dropped; `displayText` keeps the typed prompt for Muse's transcript. Remote image URLs are refused, an unreadable image refuses the turn as `attachment_unreadable`, and a turn whose input would not fit one transport frame is refused before it starts, because an oversized frame closes the connection.

MCP injection is advertised only while an initialized connection has granted `sessionMcp`. Injected stdio and streamable HTTP servers use required startup mode for both session creation and resume, so the host must report connection failures instead of silently dropping orchestration tools. Stdio MCP `cwd` remains unsupported by the native MSP schema and is rejected before session startup.

The implementation follows `@muse-code/sdk` 1.4.6 from `meta-models/muse-code-sdk` at commit `ea88c8221d381de7cb28281be8bc6b8b1507ba72`. The upstream SDK and committed protocol declarations are MIT licensed; this crate retains the accompanying MIT notice in `LICENSE-MIT`. The external host executable is not included in the upstream source repository or package and has separate licensing.
