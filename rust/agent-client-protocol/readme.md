# Upstream

This crate ports the provider-facing ACP client boundary from [reference_projects/t3code](../../reference_projects/t3code). The repository gitlink records the development reference revision. The relevant source is `packages/effect-acp/src/{client,protocol,rpc,schema}.ts`.

The ACP protocol declarations and client implementation are MIT-licensed. This Rust port keeps the wire-level behavior and retains the upstream reference as development input.

# Request callbacks

Install an `AcpClientRequestHandler` before initialization to handle peer requests. Only handlers whose `supports_terminal()` returns true advertise the ACP terminal capability. Returning `None` preserves the original request for the provider's normal event mapping and method-not-found fallback.

Callbacks run concurrently within the configured incoming capacity. A blocked terminal wait does not block permission requests, terminal control requests, notifications, or prompt responses. Handler deadlines use a monotonic clock and produce an error with code `-32001` and the original typed request id. Closing the client, a fatal transport/protocol error, or dropping the client aborts outstanding callback futures; owned processes need independent cleanup when their handler future is dropped.

Callback tasks and pending responses belong to the client, so cancellation of `next_incoming()` retains them. Responses remain in a bounded outbox until the transport confirms the write, and retrying a cancelled write keeps its original deadline. Custom transports must preserve partial writes across cancellation, as `JsonLineProcess` does. Concurrent duplicate peer request ids and queue overflow fail explicitly instead of replacing or dropping a request.

Response budgets default to the shared `ProcessConfig` frame limit. Direct SDK users with a custom limit must call `set_max_response_frame_bytes()` before receiving requests; common ACP providers configure it from their process settings. Oversized errors retain the original typed id and error code while removing optional data and shortening message text only as needed. A budget that cannot fit the required response envelope fails locally before any frame is sent; successful payloads are never silently truncated. A received request's encoded length is not treated as the transport limit because short requests do not reveal that limit.
