# Alera Cloud Operations

This runbook deploys and operates the account and push service described in [`cloud-backend.md`](cloud-backend.md). Complete the account, provider, credential, and first-deployment checklist in [`cloud-setup.md`](cloud-setup.md) before using this operational runbook. Production is `api.alera.build`; local development uses the Docker Compose Postgres service in `cloud/`. There is no staging environment in the initial cost-minimized deployment.

## Required Accounts And Tools

- Google Cloud project with billing enabled, `gcloud`, Docker, and OpenTofu 1.12.1.
- Cloudflare zone for `alera.build`, Wrangler, and a scoped API token.
- Neon Free project in a United States region.
- Google OAuth desktop client and GitHub OAuth App.
- Firebase project created by the OpenTofu root, plus an Apple developer account and APNs key only when iOS delivery is ready to verify.
- A monitored `privacy@alera.build` mailbox or alias for legal, deletion, restriction, and abuse requests.

Use a dedicated versioned Google Cloud Storage bucket for OpenTofu state. State is not a secret delivery mechanism and access must still be restricted.

## Production CD

The normal production path is `.github/workflows/cloud-deploy.yml`. A merge into `main` that changes `cloud/`, `edge/`, `infra/production/`, `tool/cloud/`, or the workflow runs the full backend, PostgreSQL, container, Edge, and OpenTofu gates before deploying. Before any build or apply, the hosted identity checks the Cloud Run service, Artifact Registry repository, versioned state bucket, and enabled versions of every required runtime secret. The workflow then builds and publishes a `linux/amd64` image, resolves its immutable digest, applies the guarded OpenTofu plan, deploys the Worker, and verifies public health, public JWKS, the expected relay state, the SQLite Durable Object namespace, and the direct-origin JWKS rejection.

The deployment job uses the `cloud-production` GitHub Environment. Google authentication is keyless through the WIF bootstrap under `infra/bootstrap/github`; Cloudflare uses independent DNS and Worker tokens. The bootstrap deployment uses its existing project IAM administration grant once to add the read-only bucket metadata role represented by `google_project_iam_member.production_state_metadata_reader`, allowing the subsequent production preflight to remain read-only. The environment is limited to `main` and has no manual approval. A push event is authorized only when its SHA is the merge commit of a pull request merged into `main`; `workflow_dispatch` from `main` is the explicit operational exception.

Manual runs support:

- `plan`: build and publish an immutable candidate image, then produce and validate the production plan without applying it.
- `deploy`: run the same path used after an authorized merge.
- `rollback`: restore an explicitly supplied full image digest and Worker version id, with the expected `disabled` or `enabled` relay state.

If verification fails after apply, the workflow first asks Cloudflare to restore the Worker version captured before deployment. Cloudflare rejects a version rollback across a Durable Object class lifecycle migration. In that case the workflow deploys the current Worker code forward with `RELAY_ENABLED=false`, which preserves the migrated namespace without exposing the relay. It then reapplies OpenTofu with the previous Cloud Run digest and repeats the namespace, health, JWKS, relay, and direct-origin probes. Structural infrastructure changes are not automatically undone. The failed run summary preserves the identifiers and expected relay state required for a manual rollback.

## Local Backend

From `cloud/`:

```sh
docker compose up -d postgres
cp .env.example .env
cargo run
```

The local configuration must set `ALERA_ALLOW_DIRECT_ORIGIN=true`, `ALERA_SIGNING_MODE=local`, and `ALERA_FCM_MODE=disabled`. Local OAuth test overrides are permitted only in local tests. Never deploy the local signing seed or direct-origin bypass.

Run the backend checks with a reachable test Postgres:

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

## OAuth Registration

Configure the Google OAuth consent screen for `openid`, `email`, and `profile`, with `https://alera.build/privacy`, `https://alera.build/terms`, and `privacy@alera.build`. Verify ownership of `alera.build`. Use a desktop OAuth client because the native runtime receives the loopback redirect.

Create a GitHub OAuth App, not a GitHub App. Use `https://alera.build` as its homepage and a loopback callback such as `http://127.0.0.1/callback`; GitHub permits the actual loopback port to vary. The application requests only `read:user user:email`.

Add both client ids to `terraform.tfvars`. Add both client secrets directly to their Secret Manager containers after bootstrap.

## Break-Glass Local Deployment

Local production deployment is reserved for recovery when GitHub Actions or its federated identity is unavailable. Record the reason, use the same immutable inputs, run the plan guard, and restore GitHub CD as soon as possible. Do not create a service-account key as a workaround.

### Infrastructure Bootstrap

Static public production values are committed in `infra/production/production.auto.tfvars`. Copy only the backend example and keep the computed image and revision in an ignored local `terraform.tfvars`:

```sh
tofu init -backend-config=backend.hcl
```

Cloud Run cannot start until Secret Manager has current versions, and the KMS public key is needed in its environment. Bootstrap the containers and signing key first:

```sh
tofu apply \
  -target=google_project_service.required \
  -target=google_artifact_registry_repository.cloud \
  -target=google_kms_crypto_key.access_tokens \
  -target=google_secret_manager_secret.runtime \
  -target=google_firebase_project.alera
```

Retrieve KMS version 1 and convert the Ed25519 SPKI public key to its raw 32-byte unpadded base64url value:

```sh
gcloud kms keys versions get-public-key 1 \
  --key=alera-access-token-signing \
  --keyring=alera-identity \
  --location=us-central1 \
  --public-key-format=pem \
  --output-file=/tmp/alera-kms-public.pem
openssl pkey -pubin -in /tmp/alera-kms-public.pem -outform DER \
  | tail -c 32 \
  | openssl base64 -A \
  | tr '+/' '-_' \
  | tr -d '='
```

Place the output in `kms_public_key_b64url`. Public key material may appear in state; private material never leaves KMS.

Populate each required secret through standard input:

```sh
gcloud secrets versions add alera-database-url --data-file=-
gcloud secrets versions add alera-edge-origin-token --data-file=-
gcloud secrets versions add alera-github-oauth-client-secret --data-file=-
gcloud secrets versions add alera-google-oauth-client-secret --data-file=-
gcloud secrets versions add alera-tombstone-pepper --data-file=-
```

Generate independent high-entropy values for the edge token and tombstone pepper. Do not reuse an OAuth client secret or copy local development values.

Cloud Run reads `latest` secret versions when instances start. Advance `cloud_run_revision` to a new lowercase marker and apply whenever a secret changes so the service deliberately creates a new revision. Do not rely on an idle instance restart to pick up a secret.

### Build And Deploy Cloud Run

Authenticate Docker to the provisioned Artifact Registry, build `cloud/Dockerfile`, push, and use the immutable digest in `cloud_run_image`:

```sh
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -t us-central1-docker.pkg.dev/PROJECT/alera-cloud/alera-cloud:BUILD ../../cloud
docker push us-central1-docker.pkg.dev/PROJECT/alera-cloud/alera-cloud:BUILD
docker inspect --format='{{index .RepoDigests 0}}' us-central1-docker.pkg.dev/PROJECT/alera-cloud/alera-cloud:BUILD
```

Review and apply the full plan:

```sh
tofu plan -out=production.tfplan
tofu show -json production.tfplan > production.tfplan.json
python3 ../../tool/cloud/validate_tofu_plan.py production.tfplan.json
tofu apply production.tfplan
```

Cloud Run scales from zero to at most two instances, uses the `alera-cloud` service account, reads secret versions at startup, signs through KMS, and sends FCM through workload identity. `/health` is the only origin route that does not require the private edge header because Cloud Run probes call it directly.

### Deploy The Cloudflare Worker

From `edge/`, install the locked dependencies and set Worker secrets:

```sh
bun install --frozen-lockfile
bunx wrangler secret put ORIGIN_BASE_URL
bunx wrangler secret put EDGE_ORIGIN_TOKEN
bun run check
bun test
bun run deploy
```

`ORIGIN_BASE_URL` is the direct `run.app` URL from `tofu output cloud_run_origin_url`. `EDGE_ORIGIN_TOKEN` is the same current value in Google Secret Manager. Wrangler owns the Worker code, route, binding, and secret values; OpenTofu owns the proxied DNS record.

Before the Worker route exists, the public hostname fails closed because it is not mapped as a Cloud Run custom domain and supported origin routes require the private header. After deployment, verify:

```sh
curl --fail https://api.alera.build/health
curl --fail https://api.alera.build/.well-known/jwks.json
tool/cloud/verify_production.sh \
  https://api.alera.build \
  "$(tofu -chdir=infra/production output -raw cloud_run_origin_url)" \
  disabled
```

Use `disabled` while the bootstrap Worker proxies `/v1/relay/deploy-probe` to the backend for a 404, and `enabled` after relay activation makes the Worker return 426 without a WebSocket upgrade. The direct Cloud Run `/health` may answer, but a direct request to any account or JWKS route must fail without the private header.

## Firebase Client Files

Use the Firebase app ids from `tofu output` to download `google-services.json` for `dev.leynier.alera_mobile` and `GoogleService-Info.plist` for `dev.leynier.aleraMobile`. These identify the Firebase project and are not service-account credentials.

Android can be verified after FCM is enabled. iOS remains prepared but unverified until the Apple developer account, signing profile, Push Notifications entitlement, and APNs authentication key in Firebase are available.

## Database Migrations

The backend runs embedded SQLx migrations before serving traffic. Deploy schema-compatible code first, use additive migrations for rolling revisions, and never remove a column while an older Cloud Run revision can still receive requests. The relay identity migration is additive and must be present before enabling Remote Access on production runtimes.

Before a destructive migration, create and test a Neon branch from production. The initial free-tier topology has one production database and no automated point-in-time recovery owned by Alera, so Neon retention and restore settings must be checked before the rollout.

## Data Cleanup

The backend performs one cleanup pass at startup and repeats it every six hours while the instance remains active. It removes expired OAuth transactions and mobile enrollments after a 24-hour grace period, revoked or expired session families after 30 days, runtime events and delivery attempts after 30 days, hourly and burst quota rows after seven days, daily quota rows after 90 days, unregistered-token tombstones after 30 days, and deleted-account tombstones after 90 days.

Cloud Run is configured with zero minimum instances. A completely idle service therefore does not promise deletion at an exact wall-clock deadline; eligible records are removed when the next instance starts. Investigate cleanup warnings in Cloud Run logs, but do not add a continuously running scheduler solely to tighten these best-effort retention windows without a cost decision.

## Edge Token Rotation

The backend accepts a current and optional previous origin token specifically for zero-downtime rotation:

1. Add the still-current token as the latest version of `alera-edge-previous-origin-token`.
2. Set `enable_previous_edge_origin_token=true`, advance `cloud_run_revision`, and apply OpenTofu. The new revision now accepts the old value through both slots.
3. Generate the replacement and add it as the latest version of `alera-edge-origin-token`.
4. Advance `cloud_run_revision` again and apply. The new revision reads the replacement as current and the old value as previous, while the older revision still accepts the old Worker value.
5. Replace the Worker's `EDGE_ORIGIN_TOKEN` with the replacement and deploy.
6. Confirm authenticated routes succeed through `api.alera.build`.
7. Set `enable_previous_edge_origin_token=false`, advance `cloud_run_revision`, apply OpenTofu, and disable the old Secret Manager version.

Never expose either token in a plan, command argument, issue, or log.

## KMS Signing-Key Rotation

Access tokens live for 15 minutes, so old verification keys must overlap the signing switch:

1. Create a new KMS version under `alera-access-token-signing`.
2. Retrieve its raw public key and choose a new unique `signing_key_id`.
3. Put the old public JWK in `previous_jwks_json`.
4. Set `kms_key_version`, `kms_public_key_b64url`, and `signing_key_id` to the new version, then apply.
5. Verify new JWT headers use the new key id and JWKS publishes both keys.
6. Wait at least 20 minutes to cover token lifetime and clock skew.
7. Set `previous_jwks_json` back to `{"keys":[]}`, apply, then disable the old KMS version.

Do not destroy a version while it appears in JWKS or can still have a valid access token.

## OAuth Secret Rotation

Create the replacement provider secret before disabling the old one. Add it as the latest Secret Manager version, advance `cloud_run_revision`, apply OpenTofu, complete one real sign-in and one link flow for that provider, then revoke the previous provider secret. Existing Alera refresh sessions remain valid because provider tokens are not retained.

## Abuse And Incident Response

The backend is authoritative for 500 daily, 60 hourly, and 10-burst account delivery limits plus five-mobile and ten-runtime ownership limits. Cloudflare adds a mutation burst limit before requests reach Cloud Run. Account suspension and global circuit-breaking are operator actions and should record a reason.

To stop all push delivery without disabling sign-in or account management, set `push_delivery_enabled=false` in the production variables, advance `cloud_run_revision`, review the plan, and apply. The backend still authenticates and validates a send, then returns `503` with `error.code=push_delivery_disabled` before it inserts a runtime event or consumes quota. Confirm the disabled response through the public edge. Restore service by setting the variable to `true`, advancing the revision marker, applying, and completing one real push.

FCM delivery makes at most three synchronous attempts per device. It waits 100 ms and 300 ms before the second and third attempts and retries only provider rate limits or transient failures. An event reserves quota once regardless of its attempt count. There is no delayed retry worker.

For suspected token leakage:

- Revoke the affected refresh-token family or account sessions.
- Rotate the edge token only if origin access may be compromised.
- Rotate the JWT signing key only if KMS authorization or signing integrity may be compromised.
- Remove an invalid FCM token rather than repeatedly retrying it.
- Preserve minimal request ids and provider response codes, never bearer tokens or notification bodies, in an incident record.

Security vulnerabilities follow [`SECURITY.md`](../SECURITY.md). Abuse or account privacy reports go to `privacy@alera.build`.

## Cost And Availability Guardrails

Cloud Run uses zero minimum instances and a maximum of two. Neon stays on its free plan, Firebase Cloud Messaging has no per-message charge, and the Worker uses its configured free-plan limits. Configure provider budget alerts even when expected spend is zero.

This is a best-effort preview with no SLA. A Cloud Run cold start or provider outage may delay or drop a notification. Do not add a durable queue, minimum instance, paid database tier, or second production region without an explicit product and cost decision.
