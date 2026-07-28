# Alera Cloud

`alera-cloud` is Alera's HTTP control plane for account identity, mobile enrollment, push subscriptions, and FCM delivery. It is intentionally separate from `rust/` and never parses or proxies the terminal-host protocol.

## Local Development

Start PostgreSQL with:

```sh
docker compose up -d --wait
```

Copy `.env.example` to an untracked `.env`, export its variables in the current shell, and run:

```sh
cargo run
```

Local mode uses a deterministic Ed25519 development seed and disables FCM. Neither setting is acceptable in production.

The service applies `migrations/` at startup, runs retention cleanup once, and repeats cleanup every six hours while an instance is active.

## HTTP Contract

All JSON uses camelCase. Every route except `GET /healthz` requires the `x-alera-origin-auth` header unless `ALERA_ALLOW_DIRECT_ORIGIN=true` is set explicitly.

| Method | Path | Authorization | Purpose |
| --- | --- | --- | --- |
| `GET` | `/healthz` | None | Container health |
| `GET` | `/.well-known/jwks.json` | Edge | Current and previous Alera signing keys |
| `POST` | `/v1/auth/transactions` | Edge | Start Google or GitHub OAuth for a runtime |
| `POST` | `/v1/auth/exchange` | Edge | Consume state, PKCE verifier, and provider code |
| `POST` | `/v1/auth/refresh` | Edge | Rotate a refresh token and issue a 15-minute access token |
| `POST` | `/v1/auth/revoke` | Edge | Revoke the refresh-token family |
| `GET` | `/v1/account` | Bearer | Account, identities, clients, and quota state |
| `POST` | `/v1/account/link` | Bearer runtime | Start a provider-link transaction |
| `DELETE` | `/v1/account` | Recent bearer | Delete account data and retain identity tombstones for 90 days |
| `POST` | `/v1/runtime/transfer` | Bearer runtime | Transfer the calling runtime and revoke its prior sessions |
| `POST` | `/v1/mobile/enrollments` | Bearer runtime | Create a five-minute device-bound enrollment code |
| `POST` | `/v1/mobile/enrollments/redeem` | Edge | Redeem once and create a scoped mobile session |
| `PUT` | `/v1/mobile/push-token` | Bearer mobile | Idempotently register the installation's FCM token |
| `DELETE` | `/v1/mobile/push-token` | Bearer mobile | Remove that account's FCM registration |
| `PUT` | `/v1/mobile/subscriptions/{runtimeId}` | Bearer mobile | Set `attention`, `done`, and `terminalExit` categories |
| `DELETE` | `/v1/mobile/subscriptions/{runtimeId}` | Bearer mobile | Remove the runtime subscription |
| `GET` | `/v1/runtime/subscriptions` | Bearer runtime | Return the authoritative active subscription count |
| `POST` | `/v1/runtime/events` | Bearer runtime | Accept an idempotent event and fan out to owned devices |

Interactive OAuth accepts only exact loopback HTTP callbacks at `127.0.0.1` or `localhost` with an explicit port and `/callback` path. Transactions expire after five minutes and are consumed before provider exchange. Google ID tokens are verified against its cached JWKS, including the RS256 signature, issuer, audience, expiry, authorized presenter, and transaction nonce. The JWKS cache honors Google's `Cache-Control` lifetime and refreshes early when a token names a new key. GitHub exchange always occurs server-side because its client secret cannot ship in Alera binaries.

Google and GitHub identities auto-link only when their normalized emails are identical and each provider marks the email verified. An identity already attached to another account is never moved by linking.

Access JWTs use EdDSA, `typ=at+jwt`, audience, client identity, session id, auth time, and explicit scopes. Refresh tokens are opaque random values stored only as SHA-256 hashes. They rotate on every use, expire after 30 days without activity or one year absolute, and any replay revokes the family.

Mobile installations are enrolled through an authenticated runtime but receive their own scoped cloud session. An FCM token may belong to several Alera accounts on the same physical installation; subscriptions and delivery ownership remain account-scoped.

## Production Configuration

Production uses `ALERA_SIGNING_MODE=google-kms`, an Ed25519 asymmetric signing key, and Cloud Run's metadata identity. `ALERA_KMS_PUBLIC_KEY_B64URL` is the raw 32-byte Ed25519 public key encoded with base64url without padding. During rotation, `ALERA_KMS_PREVIOUS_JWKS_JSON` keeps old verification keys published until every prior 15-minute access token has expired.

FCM uses the same metadata identity with `ALERA_FCM_MODE=http`. The Cloud Run service account needs only asymmetric-sign permission on its signing key and permission to send messages for the configured Firebase project.

The edge secret supports overlap through `ALERA_EDGE_PREVIOUS_ORIGIN_TOKEN`. Rotate by deploying the backend with new plus previous, changing the Worker to the new value, and then removing previous.

Limits default to 10 runtimes and 5 mobile installations per account. Push delivery defaults to 500 per UTC day, 60 per UTC hour, and 10 per minute. Each device fan-out consumes one quota unit; an idempotent duplicate consumes none.

`ALERA_PUSH_DELIVERY_ENABLED` defaults to `true`. Setting it to `false` is the global delivery circuit breaker: authenticated runtime event requests receive `503 push_delivery_disabled` before event persistence or quota consumption. Provider delivery makes at most three attempts per device, with 100 ms and 300 ms delays, and retries only rate-limited or transient FCM failures.

## Data And Retention

Provider access tokens and authorization codes are used only during exchange and are never stored. PostgreSQL stores account emails and provider ids, hashed refresh tokens, runtime and device metadata, FCM tokens required for delivery, subscriptions, event payloads, and delivery outcomes.

Cleanup removes expired OAuth transactions and enrollment codes after one day, runtime events and delivery attempts after 30 days, hourly and burst quota rows after seven days, daily quota rows after 90 days, expired or revoked sessions after their retention window, and tombstones when they expire. Cloud Run with zero minimum instances performs this work after service activity, so an entirely inactive database may retain expired operational rows until the next startup.

Account deletion removes active account data transactionally. It keeps only HMAC-protected provider-identity tombstones for 90 days to prevent immediate quota or ban reset.

## Validation

The default checks do not require PostgreSQL or network access:

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

With the Compose database running:

```sh
TEST_DATABASE_URL=postgres://alera:alera@127.0.0.1:5433/alera_cloud cargo test --workspace -- --ignored
```

The PostgreSQL contract tests cover migrations, refresh rotation and replay revocation, verified-email auto-linking, unverified-email separation, enrollment, FCM registration, subscriptions, event fan-out, and event idempotency.

## Current Boundaries

- Push sending and its bounded transient retries are synchronous. The final attempt is persisted, but a durable delayed retry worker is not part of this workspace yet.
- Runtime transfer is owner-authorized and explicitly confirmed with the runtime id, but v1 does not require a second acceptance from the target account.
- FCM is best effort. An accepted event or FCM message id is not proof that a device displayed a notification.
- A future remote terminal relay must remain opaque and end-to-end encrypted. It is not implemented here.
