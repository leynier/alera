# cursor agent sdk

This crate is a Rust client for the public `sdk.v1` Connect contract exposed by `cursor-sdk-bridge` version `1.0.35`.

The bridge executable and the embedded Cursor TypeScript SDK are external runtime dependencies. This crate does not bundle, download, or reimplement the proprietary Cursor SDK. It implements the public JSON protocol, Connect framing, bearer-token handshake inputs, agent lifecycle calls, catalog calls, and run streams.

Provision a bridge that embeds `@cursor/sdk` 1.0.38 or later. Earlier SDKs do not send Max Mode for long-context model tiers, so those tiers run without it.

Failed calls keep their typed fields: a Connect end-of-stream error becomes `CursorSdkError::Rpc` with its code, and a refused stream or non-JSON error body keeps its HTTP status. `CursorSdkError::is_usage_limit` and `is_usage_limit_code` recognize HTTP 429, `resource_exhausted`, and Cursor's usage and rate limit codes such as `PRO_USER_USAGE_LIMIT`, `RATE_LIMITED`, `USAGE_LIMIT_EXCEEDED` and `RATE_LIMIT_EXCEEDED`.

The bridge contract is MIT licensed by Anysphere, Inc. See [`LICENSE-MIT`](LICENSE-MIT). The external bridge executable and the embedded SDK must be obtained and redistributed under their own applicable terms.

Port provenance: `https://github.com/cursor/sdk-bridge`, protocol tag `v1.0.35`, checked source commit `d932194bcaf3d8ca4cae7373dfec32633ed0c9d0`, protocol manifest SDK version `1.0.35`. The port covers public `proto/sdk/v1` JSON field names, Connect HTTP/1.1 framing, service paths, handshake, stream semantics, and typed stdio/HTTP MCP server configuration. It excludes the embedded TypeScript SDK, bridge executable, host runtime, account credentials, and proprietary implementation. Hosts provide either an executable path or an already-running loopback endpoint; this crate never fetches or bundles the bridge.
