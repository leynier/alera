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

Encrypted relay envelopes larger than 48 KiB are split into ordered application-layer fragments and reassembled by the receiving peer before authenticated decryption. A complete envelope remains capped at 1 MiB. The edge forwards those fragments without interpreting them, while interrupted, out-of-order, or oversized sequences fail the connection and use the normal recovery path with a fresh grant and handshake.

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

## Connection Recovery And Presence

The mobile home screen waits for stored hosts and account initialization before publishing its initial list. Account token rotation does not invalidate that list. Discovery runs across accounts concurrently, renews expiring account sessions first, and retains the last successful remote list during temporary discovery failures. Account removal removes its cached hosts. Subsequent refreshes keep the host cards mounted, preserving their connection providers; a foreground transition after a full background state refreshes discovery, while a focus-only transition does not.

Foreground consumers share one `mobile.status.get` probe per connection. The additive `includeNetworkStatus: false` field avoids spawning Tailscale and NetBird detection commands for connection checks; an older runtime can ignore it without a protocol change. The request deadline is four seconds and removes timed-out requests from the pending map. A paired host's direct socket attempt has a three-second connection deadline before transport-only relay fallback. Optional crash-report metadata no longer delays authentication. Probe results from an earlier lifecycle transition cannot reattach a terminal after it has gone into the background.

The desktop exposes authenticated live relay peers in `connectedRelayDevices`, separate from locally paired devices. Their access comes from Cloud authorization, so the desktop does not offer the local pairing rename/revoke/delete actions for them. Disconnects emit `mobileDevicesChanged`, and disabling Remote Access disconnects all relay clients. Presence is live-only, not a durable inventory of every mobile installation on the account.

Desktop status requests that need overlay diagnostics run those commands concurrently outside the server actor, so opening Mobile Devices settings cannot delay terminal traffic or a phone's foreground probe. The actor rechecks live relay presence when the diagnostics complete rather than returning a device that disconnected while they were running.

The runtime releases peer writers and actor clients on every socket exit, including cancellation. Its relay output queue is bounded to 64 envelopes; each queued envelope carries the connection's numeric identity so frames from a replaced connection are discarded. Cloud presence refreshes run without awaiting them inside the socket forwarding branch. A 20-second WebSocket heartbeat detects a silent relay transport, writes have a five-second deadline, and the runtime starts fresh authorization before its grant expires even when idle. Grant renewal still requires reconnecting under the existing security contract; it is not seamless session renewal and does not replay commands.

The edge rejects a mobile upgrade immediately with `relay_runtime_unavailable` when no matching, unexpired runtime is connected. A disconnect is delivered once even if both error and close callbacks occur. Replaced sockets cannot forward or receive subsequent frames.

## Reliability Validation

Regression coverage includes delayed account startup, credential rotation, expired credentials, temporary discovery outages, background/resume transitions, retained host widgets, shared probes, late probe failures, local-only pairing permissions, relay peer cleanup, and edge disconnect ordering. The mobile loopback relay test performs the encrypted handshake, exchanges concurrent fragmented payloads, and reconnects using fresh ephemeral keys. Rust and Dart also share fixed cryptographic interoperability vectors.

Validation in this checkout: all 585 mobile tests, 1,295 Rust CLI unit tests (two existing ignored cases), 27 selected desktop tests, and 27 edge tests passed. Flutter analysis for desktop and mobile, Rust Clippy for all CLI targets with warnings denied, TypeScript checking, formatting checks, and `git diff --check` also passed. No production services or installed applications were changed.

Local automated tests do not measure production latency or prove Android/iOS suspension behavior. Release verification must still exercise a real phone against the updated desktop and edge: cold start, rapid app switching, a file picker round trip, Wi-Fi/cellular changes, a background interval longer than grant expiry, and a runtime restart. Confirm that terminal drafts survive, remote device presence follows the live connection, and no stale commands are replayed. Publishing or replacing the installed apps and edge is a separate operation.

## Deferred Work

The initial implementation intentionally defers key transparency, offline relay delivery, payload-aware support tooling, multi-runtime relay multiplexing, and durable connection history. Any future observability must remain metadata-only and must preserve the ciphertext-only boundary.
