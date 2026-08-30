# Alera Cloud Identity, Push And Configuration

This document defines the implemented cloud boundary for Alera accounts, mobile push delivery and manual configuration synchronization. Deployment and rotation procedures live in [`cloud-operations.md`](cloud-operations.md). Configuration documents, revisions, privacy and the additive API are described in [`configuration-sync.md`](configuration-sync.md).

## Scope

Alera remains local-first. Projects, repositories, conversation prompts, terminal input, terminal output, source code, PTYs, worktree state, and orchestration messages remain on the user's runtime. An Alera account is optional and gates shared cloud features. Configuration Sync uploads only when requested and can include reusable profile commands and prompts; the backend can read this configuration content.

The first production workload has four components:

```text
Desktop And Runtime                  Mobile
        |                               |
        | OAuth + runtime events        | enrollment + FCM token
        v                               v
Cloudflare Worker -> Cloud Run API -> Neon Postgres
                          |
                          +-> Cloud KMS signs Alera access tokens
                          |
                          +-> Firebase Cloud Messaging -> Android / iOS
```

- `cloud/` is a separate Rust workspace and Axum service. It owns identities, Alera access and refresh tokens, account limits, runtime and mobile enrollment, push subscriptions, quotas, account deletion, and FCM delivery.
- `edge/` is a narrow Cloudflare Worker. It admits the public API paths, limits mutating bursts, removes cookies, overwrites the private origin header, and proxies bytes. It does not understand the runtime-host protocol.
- `infra/production/` is the OpenTofu root for Cloud Run, KMS, Firebase app registrations, Secret Manager containers, Artifact Registry, and Cloudflare DNS.
- Neon Postgres is the portable system of record. Its credential is injected through Secret Manager and never read by OpenTofu.

## Architectural Invariants

- The cloud API never participates in the Alera runtime-host socket or WebSocket protocol.
- The future internet relay must move opaque end-to-end encrypted frames. The current backend must not become a second protocol implementation.
- Cloud agents belong to a separate compute plane that runs the real Alera runtime host. The account service may provision or authorize that plane later, but it does not emulate a PTY.
- Provider access tokens are used only to resolve identity during an OAuth exchange and are not persisted.
- No service-account private key is created. Cloud Run uses its workload identity for FCM and KMS.
- The Cloud Run origin is publicly addressable but every route except `/health` rejects a request that lacks the private edge header. Direct-origin bypass exists only behind the explicit `ALERA_ALLOW_DIRECT_ORIGIN=true` local-development setting.
- Account features are additive runtime capabilities and do not change the strict terminal-host or mobile protocol versions.

## Identity

Google and GitHub prove an external identity. The backend then emits one provider-independent Alera credential so runtimes and phones follow the same authorization path.

The native client creates a five-minute authorization transaction with a loopback redirect, random state, and PKCE S256 challenge. The provider redirects the browser to the runtime's loopback listener. The runtime sends the returned code, state, and PKCE verifier to the backend. GitHub's client secret therefore remains on the backend, not in a public binary. Google follows the same exchange path for one consistent client implementation.

Google requests only `openid email profile`. GitHub requests only `read:user user:email`, never repository access. A GitHub provider token is discarded after `/user` and `/user/emails` resolve the stable numeric id and primary verified email.

An external identity is keyed by `(provider, provider_user_id)`. When a new Google or GitHub identity has the same normalized email as an existing identity and both providers mark the email verified, the backend links it to the existing Alera account automatically. This product choice accepts the residual risk that a provider could incorrectly assert email ownership. An unverified email never auto-links. A signed-in account can also start an explicit link flow.

## Alera Sessions

An Alera access token is an Ed25519 JWT with a 15-minute lifetime, issuer and audience checks, client kind, client id, account id, scopes, authentication time, and signing-key id. Cloud KMS performs production signatures. `/.well-known/jwks.json` publishes only current and intentionally retained previous public keys.

Refresh tokens are opaque random values stored only as hashes. They rotate on every refresh, expire after 30 days without use, and have a one-year absolute lifetime. Reuse of a rotated token revokes its whole token family. A runtime or mobile sign-out revokes only that client family; account deletion removes every family.

The two client kinds receive separate least-privilege scopes:

| Client | Allowed Cloud Roles |
|---|---|
| Runtime | Read account, own runtime registration, create mobile enrollment, send runtime push events, read and publish own-account configuration |
| Mobile | Read account, register its own FCM token, manage its subscriptions, read and publish own-account configuration |

The desktop Flutter process never owns the refresh token. The runtime stores account metadata in `runtime.sqlite` and stores credentials behind the platform credential boundary, with a private-file fallback where a native keyring is unavailable. The mobile app stores each account session in platform secure storage and can retain more than one Alera account.

## Runtime And Mobile Ownership

An account can own up to ten runtimes and five mobile devices by default. Runtime ids are stable installation identities. Signing into a runtime already owned by another account does not silently move it. Transfer requires explicit confirmation, removes its outstanding mobile enrollments and subscriptions, revokes its old runtime sessions, assigns the new account, and requires authentication again.

Mobile enrollment is initiated over an authenticated paired-runtime connection and redeemed once by the phone. `mobile.hello` binds the phone's stable cloud installation id to that authenticated connection; the enrollment request takes it from the connection rather than from request payload. The short-lived internal code binds the account, runtime, mobile installation, and device label, and the mobile app redeems it directly without a second copy-and-paste step. The mobile device receives its own Alera session instead of borrowing the runtime credential.

FCM tokens and push subscriptions are central backend records. A runtime never stores a phone's FCM token. A mobile device can subscribe independently to more than one runtime under its account, and a phone with multiple Alera accounts keeps those account sessions and registrations separate.

## Push Delivery

Push is opt-in per runtime and per mobile device. Default subscriptions enable only attention events. Agent `done` and terminal-exit categories remain off until the user enables them. Supported runtime events are:

| Category | Runtime Events | Default |
|---|---|---|
| `attention` | Agent waiting, agent blocked, orchestration escalation, decision gate, coordinator stall gate | On After Opt-In |
| `done` | Agent turn finished | Off |
| `terminalExit` | Natural or explicit terminal termination | Off |

Notification titles and bodies match the desktop notification vocabulary. They may contain agent status plus project and workspace names because the user selected detailed notifications. They never contain a prompt, terminal input, terminal output, source code, or arbitrary orchestration message. The data payload carries only identifiers needed to open the associated runtime, workspace, tab, and terminal.

The runtime emits an idempotent event id. The backend records that event once, selects matching subscribed devices, enforces account quotas, sends through FCM, and records the final delivery outcome plus total synchronous attempt count. Its response also returns `activeSubscriptions`, the authoritative count of non-revoked devices with an FCM token and at least one enabled category for that runtime. `GET /v1/runtime/subscriptions` exposes the same account-owned count without creating an event, allowing the runtime to reconcile lifecycle state at startup, after opt-in, and after a paired phone changes subscription state. Creating an enrollment code alone never keeps the host alive. A device receives at most three attempts inside that request, with 100 ms and 300 ms waits before attempts two and three. Only FCM rate limits and transient transport, metadata-token, parsing, or otherwise unclassified server failures are retried. Invalid, unauthorized, disabled, and unregistered tokens fail immediately. All attempts for one device share one event record and one quota reservation.

The service does not maintain a durable retry queue. The correct failure mode after the bounded attempts is a missed non-critical notification rather than unbounded background work. The global `ALERA_PUSH_DELIVERY_ENABLED` circuit breaker defaults to `true`; when false, an authenticated and validated send returns `503 push_delivery_disabled` before the runtime event is inserted or quota is consumed.

FCM `UNREGISTERED` responses remove the stale token so later events do not retry it. Tapping an attention or gate notification opens the associated terminal when the local pairing still resolves; if the runtime or tab is unavailable, the mobile app falls back to its runtime list.

The backend defaults to 500 accepted deliveries per UTC day, 60 per hour, and a burst of 10. The Worker adds a short pre-authentication or credential-keyed mutation limit at the edge. Backend account quotas remain authoritative because network addresses are not stable user identities.

## Data Model

The initial Postgres migration separates first-class accounts from provider identities:

- `accounts` and `account_identities` hold account status and verified provider claims.
- `auth_transactions`, `refresh_token_families`, and `refresh_tokens` hold short-lived OAuth state and revocable client sessions.
- `runtimes`, `mobile_devices`, and `mobile_enrollments` hold account-owned clients and one-time enrollment state.
- `fcm_tokens` and `push_subscriptions` hold device delivery addresses and per-runtime category choices.
- `runtime_events` and `delivery_attempts` provide idempotency and delivery diagnosis.
- `push_quota_daily`, `push_quota_hourly`, and `push_quota_bursts` enforce shared-service limits.
- `abuse_tombstones` retains keyed account fingerprints for up to 90 days after deletion and non-reversible FCM token hashes for 30 days after Firebase reports a token unregistered.

Account deletion requires authentication no older than five minutes and the exact confirmation `DELETE`. The database account row is deleted with cascading removal of identities, sessions, runtimes, devices, tokens, subscriptions, events, deliveries, and quotas. A keyed 90-day tombstone is inserted before the account data is removed.

The service runs cleanup at startup and then every six hours while an instance stays active. Expired authorization transactions and mobile enrollments are eligible for deletion after 24 hours, revoked or expired session families after 30 days, runtime events and delivery attempts after 30 days, hourly and burst quota rows after seven days, daily quota rows after 90 days, and abuse tombstones when their individual expiry is reached. Cloud Run can scale to zero, so these are eligibility windows rather than exact deletion deadlines; a fully idle database is cleaned on the next service start.

## Security And Privacy Boundary

The service stores email, provider ids, runtime and device labels, FCM tokens, notification preferences, quota counters, delivery metadata, and the selected notification title/body. The primary database is configured in a United States region. Cloudflare's edge and provider security logs can process request metadata globally.

The public privacy policy is at [alera.build/privacy](https://alera.build/privacy), terms are at [alera.build/terms](https://alera.build/terms), and account deletion instructions are at [alera.build/account/delete](https://alera.build/account/delete). Security and abuse reports follow [`SECURITY.md`](../SECURITY.md).

## Explicitly Deferred

- The end-to-end encrypted internet relay, including device key agreement, recovery, rotation, and opaque multiplexing.
- Cloud-agent compute, workspace disks, Git credentials, sandboxing, suspension, and billing.
- A web account dashboard. Account management ships in the desktop and mobile apps; the static website provides legal and deletion-request surfaces only.
- A delivery SLA or durable notification outbox. The public service is best effort.
