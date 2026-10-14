# OpenCode agent SDK

This crate ports the provider-facing HTTP and Server-Sent Events client surfaces from OpenCode v1.15.13 and v2.0.23. It uses the shared HTTP transport and managed process boundary, supports injected transports in tests, and can own an external `opencode serve` process without bundling the executable.

Source provenance: https://github.com/anomalyco/opencode, legacy tag `v1.15.13`, V2 tag `v2.0.23`. The port covers client routes, UTF-8 Basic authentication, session lifecycle, model catalog, scoped MCP registration/removal, V2 permission rules, permission and form replies, bounded SSE framing, and forward-compatible execution terminal sentinels. Locally spawned V2 servers receive a generated `OPENCODE_PASSWORD`; explicit passwords and environment values take precedence.

The 1.x server exposes its configured name/status map at `GET /mcp`, dynamic registration at `POST /mcp`, and disconnect cleanup at `POST /mcp/:name/disconnect`; V2 lists configured names in the location envelope at `GET /api/mcp` and uses `PUT` and `DELETE` at `/api/experimental/mcp/:name` with directory scoping. Registration can replace native configuration; callers must check the directory's existing names and normalized namespaces before installing temporary servers. Native MCP configuration `Debug` output omits arguments, environment values, URLs, and header values.

The referenced upstream source is MIT licensed. The OpenCode executable remains an external runtime dependency and is not bundled or redistributed by this crate.

The provider's operation timeout applies to HTTP control and handshake work; the SDK's incremental SSE reader keeps an open stream until a decodable event or EOF and enforces its bound per event rather than across coalesced events.
