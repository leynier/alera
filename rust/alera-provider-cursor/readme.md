# cursor provider

This crate maps the public `cursor-sdk-bridge` `sdk.v1` contract into the shared provider event protocol. It supports one local agent session per bridge connection, create/resume, streaming turns, cancellation, model selection, plan-mode sends, bounded local image inputs, and per-session MCP server injection.

MCP stdio and HTTP specifications are translated into the bridge's `mcpServers` fields on create, resume, and send requests. The specifications belong to one provider session and are never shared through provider configuration.

Interactive approvals and user-input callbacks are reported as unsupported because the public Cursor adapter surface does not expose them. Remote image URLs, generic file attachments, snapshots, rollback, fork, and concurrent sessions are rejected explicitly.

The provider depends on [`cursor-agent-sdk`](../cursor-agent-sdk/readme.md), which is MIT licensed for its public bridge contract. The external bridge executable and embedded SDK are separate runtime dependencies.

Port provenance: `https://github.com/cursor/sdk-bridge`, protocol tag `v1.0.35`, checked source commit `d932194bcaf3d8ca4cae7373dfec32633ed0c9d0`. MIT applies to the public bridge contract; the external bridge and embedded SDK remain separate dependencies.
