# AGENTS

## Scope

This file applies to the entire `cloud/` workspace in addition to the repository root instructions.

## Service Boundary

- The cloud backend is an HTTP control plane for Alera identity, enrollment, subscription metadata, and push delivery.
- The backend MUST NOT parse, proxy, or participate in the Alera terminal-host protocol.
- Future relays MUST treat terminal traffic as opaque end-to-end encrypted bytes and remain outside this service.

## Security

- Never commit or log OAuth secrets, signing material, refresh tokens, authorization codes, FCM registration tokens, or bearer tokens.
- Access tokens MUST be short-lived and audience scoped. Refresh tokens MUST be random, stored only as hashes, rotated on use, and revoked as a family after replay.
- OAuth redirects MUST be exact loopback HTTP URLs. OAuth state, PKCE, transaction expiry, and one-time use are mandatory.
- Provider identities may auto-link only when both sides expose the same normalized email and both providers mark it verified.
- Network integrations MUST sit behind injectable interfaces so tests never contact OAuth providers, Cloud KMS, metadata servers, or FCM.

## Data

- PostgreSQL migrations are append-only after release. Never edit an applied migration; add a new one.
- Use SQLx runtime queries rather than compile-time query macros so a live database is not required to build.
- Account-owned rows MUST carry or derive an `account_id`, and every handler MUST enforce ownership at the database boundary.
- Destructive account operations must delete active personal data transactionally and retain only the documented non-reversible abuse tombstone.

## API

- Public endpoints live under `/v1` except standards-based discovery endpoints.
- JSON fields use camelCase. Error responses use a stable machine-readable code and a user-safe message.
- Runtime events are idempotent by `(runtime_id, event_id)`.
- The mobile `attention` category includes waiting, blocked, escalations, and decision gates. `done` and `terminalExit` remain separate categories.

## Quality

- Keep modules below 500 lines and split by domain responsibility.
- Run `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo test --workspace` before handoff.
- PostgreSQL integration tests may be explicitly ignored when they require the local Compose service; unit tests must run without network or external services.
