# Upstream

This crate ports the provider-facing ACP adapter boundary from [reference_projects/t3code](../../reference_projects/t3code). The repository gitlink records the development reference revision. The relevant source is `packages/provider-acp/src/server/adapter.ts` and its runtime/event helpers. The wire client is ported separately in `agent-client-protocol` from `packages/effect-acp`.

The upstream ACP declarations and adapter-facing client are MIT-licensed. This crate retains this provenance and keeps unknown ACP payloads in raw event fields. Vendor-specific executables remain external dependencies of wrappers.

# MCP Negotiation

[ACP v1](https://agentclientprotocol.com/protocol/v1/session-setup#mcp-servers) requires stdio MCP support without a capability declaration. Omitting `mcpCapabilities` or its nonstandard `stdio` field therefore keeps stdio injection available. An explicit `stdio: false` or `stdio: null` is respected as a conservative peer opt-out. HTTP requires `mcpCapabilities.http: true`.

[ACP v2](https://agentclientprotocol.com/protocol/v2/initialization#session-mcp-capabilities) requires an explicit transport declaration under `capabilities.session.mcp`, with an object advertising support and omission or `null` disabling it. The adapter also accepts boolean declarations from older peers and falls back to `sessionCapabilities.mcp` or `mcpCapabilities` only when the modern `session` field is absent. A modern disabled or incomplete session declaration cannot be overridden by legacy fields. Stdio server objects omit `type` in v1 and include `type: "stdio"` in v2.

# Reasoning Effort

Canonical `reasoningEffort` is supported only when native session `configOptions` advertises an unambiguous select option for `thought_level` or an explicit effort identifier. Exact provider values and its `configId`/`id` are sent through `session/set_config_option` before prompting. Model/configuration updates refresh the advertised choices; unknown values and absent mappings return unsupported. ACP wrappers forward the negotiated effort metadata. Native steering, fork, rollback, and filesystem rewind retain explicit unsupported defaults.
