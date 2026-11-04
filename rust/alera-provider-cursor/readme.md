# cursor provider

This crate maps the public `cursor-sdk-bridge` `sdk.v1` contract into the shared provider event protocol. It supports one local agent session per bridge connection, create/resume, streaming turns, cancellation, model selection, plan-mode sends, bounded local image inputs, and per-session MCP server injection.

MCP stdio and HTTP specifications are translated into the bridge's `mcpServers` fields on create, resume, and send requests. The specifications belong to one provider session and are never shared through provider configuration.

Stream frames that map to no event, such as Cursor's `turn-ended` update, are skipped instead of ending the event stream. After a turn ends, a retryable stream error can make Cursor's SDK resume the run from an older checkpoint; when those resumes save nothing it fails the run with `Agent turn stopped after repeated resume attempts made no progress`. If no new work followed the last `turn-ended`, the adapter completes the turn instead, drops the resume's final result text, and reports its failed status as `thread.state.changed` rather than a runtime error.

A failed turn carries `failureClass` from typed fields only: `usage_limit` when the run's `errorCode`, the Connect code of a broken stream, or the HTTP status of a refused send names a usage or rate limit (`PRO_USER_USAGE_LIMIT`, `RATE_LIMITED`, `resource_exhausted`, HTTP 429 and the like), otherwise `unknown`. A send refused on a limit fails as `ProviderError::Rejected` with that class.

Interactive approvals and user-input callbacks are reported as unsupported because the public Cursor adapter surface does not expose them. Remote image URLs, generic file attachments, snapshots, rollback, fork, and concurrent sessions are rejected explicitly.

The provider depends on [`cursor-agent-sdk`](../cursor-agent-sdk/readme.md), which is MIT licensed for its public bridge contract. The external bridge executable and embedded SDK are separate runtime dependencies.

Port provenance: `https://github.com/cursor/sdk-bridge`, protocol tag `v1.0.35`, checked source commit `d932194bcaf3d8ca4cae7373dfec32633ed0c9d0`. MIT applies to the public bridge contract; the external bridge and embedded SDK remain separate dependencies.

Canonical `reasoningEffort` uses the selected model's advertised parameter definition and exact `model.params[{id,value}]` fields on create/resume/send. Authenticated model discovery and an explicit model are required; absent, ambiguous, or unadvertised values fail as unsupported. The exported metadata helpers derive choices and defaults from typed native model parameters and variants, never from model names.
