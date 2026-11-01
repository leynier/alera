# Upstream

This crate ports the provider-facing ACP adapter boundary from [reference_projects/t3code](../../reference_projects/t3code). The repository gitlink records the development reference revision. The relevant source is `packages/provider-acp/src/server/adapter.ts` and its runtime/event helpers. The wire client is ported separately in `agent-client-protocol` from `packages/effect-acp`.

The upstream ACP declarations and adapter-facing client are MIT-licensed. This crate retains this provenance and keeps unknown ACP payloads in raw event fields. Vendor-specific executables remain external dependencies of wrappers.

# MCP Negotiation

[ACP v1](https://agentclientprotocol.com/protocol/v1/session-setup#mcp-servers) requires stdio MCP support without a capability declaration. Omitting `mcpCapabilities` or its nonstandard `stdio` field therefore keeps stdio injection available. An explicit `stdio: false` or `stdio: null` is respected as a conservative peer opt-out. HTTP requires `mcpCapabilities.http: true`.

[ACP v2](https://agentclientprotocol.com/protocol/v2/initialization#session-mcp-capabilities) requires an explicit transport declaration under `capabilities.session.mcp`, with an object advertising support and omission or `null` disabling it. The adapter also accepts boolean declarations from older peers and falls back to `sessionCapabilities.mcp` or `mcpCapabilities` only when the modern `session` field is absent. A modern disabled or incomplete session declaration cannot be overridden by legacy fields. Stdio server objects omit `type` in v1 and include `type: "stdio"` in v2.

# Reasoning Effort

Canonical `reasoningEffort` is supported only when native session `configOptions` advertises an unambiguous select option for `thought_level` or an explicit effort identifier. Exact provider values and its `configId`/`id` are sent through `session/set_config_option` before prompting. Model/configuration updates refresh the advertised choices; unknown values and absent mappings return unsupported. ACP wrappers forward the negotiated effort metadata. Native steering, fork, rollback, and filesystem rewind retain explicit unsupported defaults.

# Tool Calls

A `tool_call` or `tool_call_update` with a terminal status completes its item. `cancelled` and `canceled` settle the item as failed, as in T3 Code, so a call the agent abandons never stays running after its turn ends; `declined` keeps its own status, and an unknown status reads as in progress. The registry's Copilot flavor reports a cancelled or stopped task as `cancelled`, which the chat shows as stopped.

# Turn Errors

A failed turn keeps what the agent said about the failure. Its `turn.completed` takes `errorMessage` from the first non-blank `errorMessage`, string `error` or `error.message`, and a structured `error` object adds `error {code, data}`, the shape a failed prompt RPC already has. This holds for the idle `state_update` with `stopReason: "error"` that ACP v2 agents send for a failed prompt, such as `{"sessionUpdate":"state_update","state":"idle","stopReason":"error","error":{"code":-32000,"message":"Missing Authentication header","data":{"retry":false}}}`, for every ACP flavor, and for the x.ai `turn_completed` and `prompt_complete` frames. Grok's completion can arrive before the prompt's RPC error, so a failed x.ai completion without error text uses its non-blank `agentResult`. An idle error without details fails the turn with no `errorMessage`. The code alone sets no `failureClass`; a wrapper flavor may classify it, as the registry does for Mistral's rate limit. This follows T3 Code `012e4ec056` (keep the error of a failed v2 idle), `5a969c17e7` (idle errors fail their turns) and the Grok `agentResult` failure in `packages/provider-grok/src/server/xaiAcpExtension.ts`.

On ACP v2, which the client detects from an `initialize` result with `info` or `capabilities` rather than from `protocolVersion`, a `session/prompt` response without `stopReason`, such as `{"messageId":"user-3"}`, only accepts the prompt, and the root idle `state_update` ends the turn, failing it on `stopReason: "error"`, as T3 Code's client waits for that idle. An idle that arrives before the response also ends the turn, and the late response is ignored. A response that carries a stop reason, or an RPC error, still ends the turn at once. The agent may still send that prompt's idle, so until the agent accepts the next prompt or reports another state, an idle counts as the owed one and does not end the next turn. With native child sessions the adapter keeps its own rule: an idle ends the turn only after acceptance or a `running` state. An ACP v1 prompt response always ends the turn.

An idle error while no turn runs, such as one the agent sends after a turn already ended, becomes `runtime.error` with `message`, `code` and `data`, which the chat shows as an error notice. It is skipped when the last turn failed, since it repeats that failure, and when it carries no error text. T3 Code drops such an idle.
