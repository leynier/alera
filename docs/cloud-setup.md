# Alera Cloud Setup

This guide describes every account, provider registration, credential, infrastructure resource, and client configuration required to operate Alera accounts and mobile push delivery in production.

The supported production topology is:

```text
Desktop runtime
  -> Google or GitHub OAuth
  -> api.alera.build
  -> Cloudflare Worker
  -> Cloud Run
  -> Neon Postgres
  -> Firebase Cloud Messaging
  -> Android or iOS app
```

The first verified target is Android. The iOS project is prepared, but real iOS delivery additionally requires Apple signing and APNs configuration.

## Important Boundaries

- Alera accounts are optional for all local features.
- Firebase Authentication is not used. Alera exchanges Google and GitHub authorization codes and issues its own short-lived access tokens.
- The mobile app does not sign in to Google or GitHub. It inherits account access through enrollment with an authenticated desktop runtime.
- Firebase is used only for Cloud Messaging and mobile app registration.
- No service-account private key is downloaded or stored. Cloud Run uses its Google service account through workload identity.
- The backend is an HTTP control plane. It does not parse or proxy the terminal-host protocol.
- Production secrets must not be committed, placed in OpenTofu state, passed in shell arguments, or sent through chat.
- AWS, a VPS, and Firebase Authentication are not required for this topology.

## Account Inventory

Create or confirm access to the following accounts before starting.

| Provider | Required Now | Purpose |
| --- | --- | --- |
| Google Cloud | Yes | Cloud Run, Artifact Registry, Cloud KMS, Secret Manager, Firebase, and remote OpenTofu state |
| Google OAuth | Yes | Google identity provider for desktop sign-in |
| GitHub | Yes | GitHub OAuth App for desktop sign-in |
| Neon | Yes | Production Postgres database |
| Cloudflare | Yes | `alera.build` DNS zone and API Worker |
| Vercel or current landing host | Yes | Public privacy, terms, deletion, and sign-in success pages |
| Monitored email provider | Yes | `privacy@alera.build` privacy, deletion, restriction, and abuse requests |
| Apple Developer Program | No, Android only | iOS signing, provisioning, Push Notifications capability, and APNs key |
| Tailscale | Optional | Recommended private connectivity for initial desktop-to-mobile pairing |

The same Google Cloud project owns Cloud Run and Firebase. Do not create a separate Firebase project unless the architecture is intentionally changed.

## Operator Tooling

Install `gcloud`, Docker with a running daemon, OpenTofu 1.12.1, Bun, Wrangler through the locked `edge/` dependencies, OpenSSL, and GitHub CLI on the operator machine.

Authenticate Google Cloud before running OpenTofu:

```sh
gcloud auth login
gcloud auth application-default login
gcloud config set project alera-production
```

OpenTofu uses Google Application Default Credentials. Do not create a long-lived service-account key for local deployment.

## Public Legal Pages And Contact

Deploy these existing landing pages publicly before publishing the Google OAuth consent screen:

- `https://alera.build/privacy`
- `https://alera.build/terms`
- `https://alera.build/account/delete`
- `https://alera.build/signed-in`

Create `privacy@alera.build` as a monitored mailbox or forwarding alias. Cloudflare Email Routing is sufficient if the domain already uses Cloudflare. The address must reach a mailbox that is regularly monitored because the published policy directs account deletion, privacy, restriction, and abuse requests there.

Verify that every page returns `200`, uses HTTPS, and is accessible without authentication:

```sh
curl --fail https://alera.build/privacy
curl --fail https://alera.build/terms
curl --fail https://alera.build/account/delete
curl --fail https://alera.build/signed-in
```

## Google Cloud Project

Create one production Google Cloud project. The examples use `alera-production`, but the final project id may differ.

Required manual configuration:

1. Link an active billing account.
2. Configure a low budget alert even when expected spend is zero.
3. Restrict project administrators to the minimum set of maintainers.
4. Use `us-central1` unless there is an explicit data residency decision.
5. Verify ownership of `alera.build` for the OAuth consent screen.

OpenTofu enables Artifact Registry, Cloud KMS, Firebase Management, Firebase Cloud Messaging, IAM Credentials, Cloud Run, Secret Manager, and Service Usage.

It creates the `alera-cloud` Docker repository, Cloud Run service and service account, the Ed25519 KMS signing key, Secret Manager containers, the Firebase project binding, Android app `dev.leynier.alera_mobile`, Apple app `dev.leynier.aleraMobile`, and the proxied Cloudflare DNS record for `api.alera.build`.

## OpenTofu State Bucket

Create a dedicated private and versioned Google Cloud Storage bucket before initializing OpenTofu. The bucket must not be shared with application data.

Example:

```sh
gcloud storage buckets create gs://alera-production-opentofu-state \
  --location=us-central1 \
  --uniform-bucket-level-access
gcloud storage buckets update gs://alera-production-opentofu-state --versioning
gcloud storage buckets describe gs://alera-production-opentofu-state \
  --format="default(versioning_enabled)"
```

The final command must report `versioning_enabled: true`. The hosted production preflight checks the same metadata before it builds or applies anything.

Restrict access to the operators who manage production infrastructure. The state does not contain runtime secrets, but it does contain project identifiers, OAuth client ids, public signing material, and the direct Cloud Run origin URL.

Copy the backend configuration:

```sh
cd infra/production
cp backend.hcl.example backend.hcl
```

Set:

```hcl
bucket = "alera-production-opentofu-state"
prefix = "alera/production"
```

`backend.hcl` is ignored by Git and must remain uncommitted.

## Google OAuth Registration

Configure Google Auth Platform in the production Google Cloud project.

Consent screen:

- Application name: `Alera`
- Audience: External
- Support email: a monitored project address
- Privacy policy: `https://alera.build/privacy`
- Terms of service: `https://alera.build/terms`
- Authorized domain: `alera.build`
- Developer contact: `privacy@alera.build`
- Scopes: `openid`, `email`, and `profile`

Add the operator Google account as a test user for the first end-to-end test. Publish the application when sign-in must be available beyond the configured test users.

Create an OAuth client:

- Application type: Desktop app
- Name: `Alera Desktop`

Desktop clients support dynamic loopback redirects such as `http://127.0.0.1:<port>/callback`. Do not create a web client for the desktop runtime.

Record:

- Client id: public configuration in `terraform.tfvars`
- Client secret: secret value added to `alera-google-oauth-client-secret`

The backend verifies the Google ID token, including signature, issuer, audience, authorized presenter, expiry, and nonce. Provider tokens are discarded after identity resolution.

## GitHub OAuth Registration

Create a GitHub OAuth App, not a GitHub App. It may be owned by the maintainer account or by an organization where the operator has administrative access.

Configuration:

- Application name: `Alera`
- Homepage URL: `https://alera.build`
- Authorization callback URL: `http://127.0.0.1/callback`
- Device Flow: disabled

The runtime supplies the actual loopback port. GitHub permits a loopback redirect to vary the port while preserving the registered host and path.

The application requests only:

- `read:user`
- `user:email`

Never request repository scopes for account sign-in.

Generate a client secret and record:

- Client id: public configuration in `terraform.tfvars`
- Client secret: secret value added to `alera-github-oauth-client-secret`

GitHub access tokens are used once to resolve the numeric user id and verified primary email, then discarded.

## Neon Postgres

Create a Neon project on the Free plan in a United States region.

Create or identify the production database and obtain:

- Neon project id
- Production Postgres connection URL

The connection URL must require TLS. Store the complete URL only in the `alera-database-url` Secret Manager secret. OpenTofu records the Neon project id but never reads or stores the database password.

Do not use the local Docker Compose credentials in production.

The backend runs embedded SQLx migrations before accepting traffic. Check Neon retention and branch restore options before any destructive schema change.

## Cloudflare Zone And Tokens

Confirm that `alera.build` is an active Cloudflare zone.

Use scoped API tokens instead of the global API key. Two tokens are recommended so DNS provisioning and Worker deployment can be revoked independently.

OpenTofu token:

- Zone Read for `alera.build`
- DNS Edit for `alera.build`

Wrangler token:

- Workers Scripts Write for the selected Cloudflare account
- Workers Routes Edit for `alera.build`
- Zone Read for `alera.build`

Set the appropriate token only in the operator shell:

```sh
export CLOUDFLARE_API_TOKEN="<scoped-token>"
```

Do not put the token in `terraform.tfvars`, Wrangler configuration, GitHub issues, or shell scripts.

OpenTofu creates the proxied CNAME for `api.alera.build`. Do not create a competing DNS record manually. Wrangler owns the Worker code, route, rate-limit binding, and Worker secrets.

## Production OpenTofu Variables

Copy the ignored variable file:

```sh
cd infra/production
cp terraform.tfvars.example terraform.tfvars
```

Populate the non-secret values:

```hcl
gcp_project_id         = "alera-production"
gcp_region             = "us-central1"
cloud_run_image        = "us-central1-docker.pkg.dev/alera-production/alera-cloud/alera-cloud@sha256:replace-after-build"
cloud_run_revision     = "initial"
cloudflare_zone_id     = "replace-with-zone-id"
api_hostname           = "api.alera.build"
google_oauth_client_id = "replace-with-google-client-id"
github_oauth_client_id = "replace-with-github-client-id"
neon_project_id        = "replace-with-neon-project-id"
signing_key_id         = "alera-production-v1"
kms_key_version        = "1"
kms_public_key_b64url  = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
previous_jwks_json     = "{\"keys\":[]}"
push_delivery_enabled = true
```

The placeholder image must still satisfy the digest validation during targeted bootstrap. Replace it with the real immutable digest before the complete plan.

`terraform.tfvars` is ignored by Git and must remain uncommitted.

## Infrastructure Bootstrap

Initialize the production root:

```sh
cd infra/production
tofu init -backend-config=backend.hcl
```

Bootstrap the APIs and resources needed before Cloud Run can start:

```sh
tofu apply \
  -target=google_project_service.required \
  -target=google_artifact_registry_repository.cloud \
  -target=google_kms_crypto_key.access_tokens \
  -target=google_secret_manager_secret.runtime \
  -target=google_firebase_project.alera
```

Review the target plan before approving it. The targeted apply creates containers and signing material but does not produce a usable Cloud Run deployment.

## KMS Public Key

Retrieve KMS key version 1 and convert its Ed25519 SPKI public key to the raw 32-byte unpadded base64url value using the exact commands in [`cloud-operations.md`](cloud-operations.md#infrastructure-bootstrap). Place the result in `kms_public_key_b64url`, then delete the temporary PEM.

The value is public signing-key material and may appear in OpenTofu state. The private signing key never leaves Cloud KMS.

## Secret Manager Values

OpenTofu creates six secret containers. Five require initial values:

| Secret | Value |
| --- | --- |
| `alera-database-url` | Neon production Postgres URL |
| `alera-edge-origin-token` | Independent high-entropy random origin token |
| `alera-github-oauth-client-secret` | GitHub OAuth App client secret |
| `alera-google-oauth-client-secret` | Google desktop OAuth client secret |
| `alera-tombstone-pepper` | Independent random value with at least 32 characters |
| `alera-edge-previous-origin-token` | Leave without a version until an edge-token rotation |

Add values through standard input:

```sh
gcloud secrets versions add alera-database-url --data-file=-
gcloud secrets versions add alera-edge-origin-token --data-file=-
gcloud secrets versions add alera-github-oauth-client-secret --data-file=-
gcloud secrets versions add alera-google-oauth-client-secret --data-file=-
gcloud secrets versions add alera-tombstone-pepper --data-file=-
```

Use a password manager or secure random generator for the origin token and tombstone pepper. They must be unrelated values and must not reuse either OAuth secret.

Cloud Run reads the `latest` enabled version when an instance starts. After changing a secret, advance `cloud_run_revision` to a new lowercase marker and apply OpenTofu so every intended instance uses the new version.

## Cloud Run Image And Complete Apply

Authenticate Docker to `us-central1-docker.pkg.dev`, build `cloud/Dockerfile`, push it to the provisioned `alera-cloud` Artifact Registry repository, and obtain its immutable repository digest. The exact build and inspection commands are in [`cloud-operations.md`](cloud-operations.md#build-and-deploy-cloud-run).

Set the complete `@sha256:` value as `cloud_run_image`. Tags are not accepted for production deployment. Switch `CLOUDFLARE_API_TOKEN` to the scoped OpenTofu token, then review and apply the complete plan:

```sh
cd infra/production
tofu plan -out=production.tfplan
tofu apply production.tfplan
```

Inspect the outputs:

```sh
tofu output
tofu output -raw cloud_run_origin_url
tofu output -raw public_api_url
```

Cloud Run is configured with zero minimum instances and at most two instances. It signs access tokens through KMS and sends FCM messages through its workload identity.

Only `/health` is intentionally reachable at the direct Cloud Run origin without the private edge header.

## Cloudflare Worker Deployment

Switch `CLOUDFLARE_API_TOKEN` to the scoped Wrangler token.

From `edge/`:

```sh
bun install --frozen-lockfile
bunx wrangler secret put ORIGIN_BASE_URL
bunx wrangler secret put EDGE_ORIGIN_TOKEN
bun run check
bun test
bun run deploy
```

Enter:

- `ORIGIN_BASE_URL`: exact `tofu output -raw cloud_run_origin_url` value
- `EDGE_ORIGIN_TOKEN`: exact current value stored in `alera-edge-origin-token`

The Worker removes cookies, overwrites the origin-authentication header, admits only supported paths, applies the mutation burst limit, and forwards requests to Cloud Run.

Verify the public edge:

```sh
curl --fail https://api.alera.build/health
curl --fail https://api.alera.build/.well-known/jwks.json
```

Verify the origin boundary:

- Direct Cloud Run `/health` may succeed.
- Direct Cloud Run account, push, and JWKS routes must fail without the edge header.
- Public `api.alera.build` routes must pass through the Worker.

## Firebase Client Configuration

After the full apply, inspect:

```sh
cd infra/production
tofu output firebase_android_app_id
tofu output firebase_apple_app_id
```

In Firebase Console, open Project Settings and download:

- `google-services.json` for package `dev.leynier.alera_mobile`
- `GoogleService-Info.plist` for bundle `dev.leynier.aleraMobile`

These files identify the Firebase project. They are not service-account credentials, but production Firebase values are intentionally not stored in this repository.

For local Android verification, either place the real file at:

```text
mobile/android/app/google-services.json
```

or pass all four Dart definitions:

```sh
flutter run \
  --dart-define=ALERA_FIREBASE_API_KEY=... \
  --dart-define=ALERA_FIREBASE_APP_ID=... \
  --dart-define=ALERA_FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=ALERA_FIREBASE_PROJECT_ID=...
```

The mobile cloud client defaults to `https://api.alera.build/`. Override it only for explicit local development with `ALERA_CLOUD_BASE_URL`.

Android test devices must have compatible Google Play Services. A force-stop from Android system settings blocks FCM delivery until the app is opened again.

## Android Release Configuration

The release workflow already requires these GitHub repository secrets for stable APK signing:

- `ALERA_ANDROID_KEYSTORE_BASE64`
- `ALERA_ANDROID_KEYSTORE_PASSWORD`
- `ALERA_ANDROID_KEY_ALIAS`
- `ALERA_ANDROID_KEY_PASSWORD`

Keep a protected backup of the upload keystore outside GitHub. Losing it prevents existing users from installing updates signed by a replacement key.

The release workflow requires these GitHub repository variables and passes them as `--dart-define` values to both Android build commands:

- `ALERA_FIREBASE_API_KEY`
- `ALERA_FIREBASE_APP_ID`
- `ALERA_FIREBASE_MESSAGING_SENDER_ID`
- `ALERA_FIREBASE_PROJECT_ID`

Firebase client identifiers are not private credentials, but they remain out of source to preserve the repository's current environment boundary. The workflow fails before building an APK when any required variable is missing because an APK without this configuration cannot register for Alera FCM delivery.

## Android End-To-End Verification

Complete this sequence with a real Android device:

1. Confirm `https://api.alera.build/health` and JWKS succeed.
2. Start the desktop app and open Settings > Account.
3. Sign in with GitHub and confirm the loopback browser flow returns to Alera.
4. Sign out, then sign in with Google using the same verified email and confirm it resolves to the same Alera account.
5. Restart the runtime and confirm the Alera session persists without reopening the browser.
6. Enable mobile access, pair the Android phone, enable push, and accept notification permission.
7. Confirm the account, runtime, mobile device, and push subscription appear in desktop settings.
8. Close the mobile app without force-stopping it, trigger an agent `waiting` or `blocked` transition, and confirm the notification arrives.
9. Tap the notification and confirm the app opens the intended runtime, workspace, and tab.
10. Repeat in the foreground, trigger two close events, and confirm deduplication and aggregation.
11. Test `done`, orchestration decision, and terminal-exit categories according to their settings.
12. Confirm desktop sign-out, mobile revocation, and test-account deletion each stop the corresponding access.

Keep notification bodies free of prompts, commands, terminal input, and terminal output. Only the selected state plus project and workspace names may cross the push provider boundary.

## iOS Setup

Do not treat iOS as verified until all of these are complete:

- Active Apple Developer Program membership
- Registered App ID for `dev.leynier.aleraMobile`
- Distribution and development signing configuration
- Provisioning profiles
- Push Notifications capability
- Background Modes with Remote Notifications
- APNs authentication key
- APNs key id and Apple team id
- APNs key uploaded under the Firebase Apple app Cloud Messaging settings
- Real-device background and cold-start verification

The `.p8` APNs key is private material. Store it in the Apple and Firebase consoles and in the operator password manager, never in the repository.

## Cost And Availability Guardrails

The initial deployment is deliberately cost-minimized: Cloud Run scales from zero to at most two instances, Neon and the Cloudflare Worker use their free plans, Firebase Cloud Messaging has no per-message charge, and there is no durable queue, continuously running cleanup scheduler, staging environment, or second production region.

Billing must still remain enabled for Google Cloud. Configure budget alerts and periodically review Cloud Run, Artifact Registry, KMS, Secret Manager, Cloudflare, and Neon usage.

This is a best-effort preview with no SLA. Cold starts and provider outages may delay or drop a notification.

## Completion Checklist

- [ ] Legal pages are live, `privacy@alera.build` is monitored, and Google owns the verified domain.
- [ ] Google Cloud billing, budget alerts, and the versioned GCS state bucket are configured.
- [ ] Google Desktop OAuth, GitHub OAuth App, Neon Postgres, and scoped Cloudflare tokens are configured.
- [ ] OpenTofu bootstrap completed.
- [ ] KMS public key and all five initial Secret Manager values are configured.
- [ ] The digest-pinned Cloud Run image and complete OpenTofu apply succeeded.
- [ ] Cloudflare Worker secrets and deployment succeeded, public checks pass, and the direct origin fails closed.
- [ ] Firebase Android configuration and release injection are available.
- [ ] Android signing secrets and the external keystore backup are verified.
- [ ] Google and GitHub sign-in plus Android background and cold-start push pass end to end.
- [ ] Sign-out, device revocation, and account deletion stop their corresponding access.
- [ ] Apple and APNs setup is completed before claiming iOS support.

## Related Runbooks

- [`cloud-backend.md`](cloud-backend.md) describes the architecture and trust boundaries.
- [`cloud-operations.md`](cloud-operations.md) describes deployment, rotation, cleanup, incident response, and operational procedures.
- [`../infra/production/readme.md`](../infra/production/readme.md) describes the OpenTofu root.
- [`../edge/readme.md`](../edge/readme.md) describes the Cloudflare Worker.
- [`../cloud/readme.md`](../cloud/readme.md) describes backend routes and runtime configuration.
- [`../mobile/readme.md`](../mobile/readme.md) describes mobile Firebase and release behavior.
- [`release-trust.md`](release-trust.md) describes release signing and artifact trust.
