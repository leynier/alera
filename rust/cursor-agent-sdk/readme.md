# cursor agent sdk

This crate is a Rust client for the public `sdk.v1` Connect contract exposed by `cursor-sdk-bridge` version `1.0.35`.

The bridge executable and the embedded Cursor TypeScript SDK are external runtime dependencies. This crate does not bundle, download, or reimplement the proprietary Cursor SDK. It implements the public JSON protocol, Connect framing, bearer-token handshake inputs, agent lifecycle calls, catalog calls, and run streams.

The bridge contract is MIT licensed by Anysphere, Inc. See [`LICENSE-MIT`](LICENSE-MIT). The external bridge executable and the embedded SDK must be obtained and redistributed under their own applicable terms.

Port provenance: `https://github.com/cursor/sdk-bridge`, protocol tag `v1.0.35`, checked source commit `d932194bcaf3d8ca4cae7373dfec32633ed0c9d0`, protocol manifest SDK version `1.0.35`. The port covers public `proto/sdk/v1` JSON field names, Connect HTTP/1.1 framing, service paths, handshake, stream semantics, and typed stdio/HTTP MCP server configuration. It excludes the embedded TypeScript SDK, bridge executable, host runtime, account credentials, and proprietary implementation. Hosts provide either an executable path or an already-running loopback endpoint; this crate never fetches or bundles the bridge.
