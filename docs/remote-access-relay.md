# Remote Access Relay

Remote Access is an explicit per-runtime opt-in. It lets an authenticated Alera mobile installation discover and connect to an active runtime through a direct local path first and an opaque Cloudflare Durable Object relay only when the direct transport fails.

## Flow

1. A desktop user enables `Enable Remote Access` in Mobile Gateway settings. The setting is stored in the runtime database and defaults to off.
2. The runtime signs in through the existing account service, registers an X25519-compatible identity public key, and keeps its private key in the local credential store.
3. The mobile app signs in directly with Google or GitHub through an external browser, using PKCE and a loopback callback where the platform permits it. It keeps a separate installation identity key in secure storage and registers only the public key.
4. The mobile app discovers active runtimes belonging to the same account. It tries a paired LAN, Tailnet, or VPN endpoint first. Only a transport failure permits relay fallback; authentication, authorization, protocol, and cryptographic failures are surfaced.
5. The cloud checks account ownership, client registration, runtime activity, revocation, and role before issuing a 120-second grant. The edge verifies the signed grant and routes the WebSocket to the Durable Object named for that runtime. An endpoint cannot forward another frame after its grant expires, so reconnection obtains a fresh authorization decision.
6. The runtime and mobile app complete the versioned E2E handshake, confirm the transcript, and exchange the existing mobile runtime protocol inside encrypted envelopes. Binary terminal frames and future additive capabilities remain opaque to the edge.

## Threat Model

The cloud account authority is trusted to authenticate accounts, authorize runtime ownership, register or revoke identity public keys, and sign short-lived grants. Account deletion, refresh-token revocation, runtime transfer, device revocation, and key rotation are authority operations.

The relay is treated as hostile transport infrastructure. It can observe connection metadata, timing, frame sizes, peer count, and whether forwarding succeeds. It cannot read terminal commands, terminal output, workspace content, protocol JSON, or binary frames because those are encrypted end to end. The relay has no payload storage, queue, timer, alarm, or outbound socket.

The handshake binds the account, runtime id, mobile id, both static identity keys, both ephemeral keys, and a fresh nonce. Its role-specific confirmations prevent either side's confirmation from being reflected back as proof of the other role. HKDF-SHA256 derives independent client-to-runtime and runtime-to-client keys. ChaCha20-Poly1305 uses a direction-specific nonce derived from a strictly monotonic counter; counter gaps, replay, altered ciphertext, wrong peers, and transcript mismatches are rejected.

The first release does not provide key transparency. The account authority can maliciously substitute a registered public key, and a compromised account can authorize its own devices. Users should revoke the account or installation after suspected credential compromise. This limitation is deliberate and must not be described as protection against a malicious identity authority.

## Privacy Boundary

The cloud stores account and runtime metadata plus public identity keys. It stores no private identity keys, relay grants, relay frames, commands, output, or workspace content. The edge and Durable Object may retain provider request logs and platform connection metadata according to the provider's operational retention, so logs must never include bearer grants, identity private material, frame payloads, or decrypted content.

Remote access is live-only. Disconnecting either endpoint loses in-flight data; no command or output is queued for later delivery. Reconnect obtains a fresh grant and performs a fresh handshake. Removing an account from the phone revokes its cloud refresh-token family before deleting the local session.

## Operations

- Keep `ALERA_RELAY_BASE_URL` aligned with the public Worker route. Production uses `wss://api.alera.build/v1/relay`.
- Keep `RELAY_ISSUER` and `RELAY_JWKS_URL` in the Worker configuration aligned with the cloud issuer and public JWKS endpoint.
- Deploy the additive SQL migration before relying on relay identity registration. Existing runtimes remain compatible because the setting and identity rows default to disabled or absent.
- Treat the relay mobile connection limit, frame size limit, and 120-second grant lifetime as security and cost controls. Change them only with matching cloud, edge, Rust, mobile, and test updates.
- On suspected account or key compromise, revoke the account or mobile installation, rotate the affected identity key with a higher key version, and verify that discovery and grant issuance stop for revoked records.

## Deferred Work

The initial implementation intentionally defers key transparency, offline relay delivery, payload-aware support tooling, multi-runtime relay multiplexing, and durable connection history. Any future observability must remain metadata-only and must preserve the ciphertext-only boundary.
