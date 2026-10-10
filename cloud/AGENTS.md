# AGENTS

## Scope

This file applies to the entire `cloud/` workspace in addition to the repository root instructions.

## Service Boundary

- The cloud backend is an HTTP control plane for Alera identity, enrollment, subscription metadata, and push delivery.
- The backend MUST NOT parse, proxy, or participate in the Alera terminal-host protocol.
- Future relays MUST treat terminal traffic as opaque end-to-end encrypted bytes and remain outside this service.
- Remote MCP is the documented exception (`docs/remote-mcp.md`): for runtimes that opt in to MCP Control, tool arguments and results pass through the edge in plaintext. The cloud only authorizes calls, signs call grants, and records metadata-only audit rows; it never stores or logs tool arguments or results, and it never parses the terminal-host protocol.

## Security

- Never commit or log OAuth secrets, signing material, refresh tokens, authorization codes, FCM registration tokens, or bearer tokens.
- Access tokens MUST be short-lived and audience scoped. Refresh tokens MUST be random, stored only as hashes, rotated on use, and revoked as a family after replay.
- Native sign-in redirects MUST be exact loopback HTTP URLs. MCP client redirects MUST exactly match a registered URI and follow the rules in `docs/remote-mcp.md` (HTTPS, loopback HTTP, or private-use schemes). OAuth state, PKCE, transaction expiry, and one-time use are mandatory.
- Each MCP client has exactly one token endpoint authentication method (`none` or `private_key_jwt`) and `/oauth/token` MUST enforce that method, never accept either. `private_key_jwt` assertions are single-use by `jti`, and the client MUST be authenticated before an authorization code is consumed.
- Pages served by the authorization server MUST escape every user or client string, send `frame-ancestors 'none'`, and carry the consent state in single-use form tokens, because the edge removes cookies.
- Provider identities may auto-link only when both sides expose the same normalized email and both providers mark it verified.
- Network integrations MUST sit behind injectable interfaces so tests never contact OAuth providers, Cloud KMS, metadata servers, or FCM.

## Data

- PostgreSQL migrations are append-only after release. Never edit an applied migration; add a new one.
- Use SQLx runtime queries rather than compile-time query macros so a live database is not required to build.
- Account-owned rows MUST carry or derive an `account_id`, and every handler MUST enforce ownership at the database boundary.
- Destructive account operations must delete active personal data transactionally and retain only the documented non-reversible abuse tombstone.

## API

- Public endpoints live under `/v1` except standards-based discovery endpoints and the OAuth endpoints under `/oauth` and `/device`.
- JSON fields use camelCase. Error responses use a stable machine-readable code and a user-safe message. Standards-based OAuth endpoints use their RFC field names and `{ error, error_description }` errors instead.
- Runtime events are idempotent by `(runtime_id, event_id)`.
- The mobile `attention` category includes waiting, blocked, escalations, and decision gates. `done` and `terminalExit` remain separate categories.

## Quality

- Keep modules below 500 lines and split by domain responsibility.
- Run `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace` before handoff.
- PostgreSQL integration tests may be explicitly ignored when they require the local Compose service; unit tests must run without network or external services.
