# Production Infrastructure

This OpenTofu root creates Alera's Google Cloud and Cloudflare production resources: required APIs, Artifact Registry, the Cloud Run service, its least-privilege service account, Secret Manager containers, an Ed25519 Cloud KMS signing key, Firebase Android and Apple app registrations, and the proxied `api.alera.build` DNS record.

Neon remains an external free-tier service by design. `neon_project_id` records the selected project, while the database connection URL is added directly to Google Secret Manager. OpenTofu never queries or stores the Neon role password.

## Prerequisites

- An existing Google Cloud project with billing enabled.
- An existing versioned Google Cloud Storage bucket for OpenTofu state.
- An existing Neon project in a United States region.
- A Cloudflare API token provided through `CLOUDFLARE_API_TOKEN`.
- Google Application Default Credentials with permission to manage the declared resources.
- Google desktop OAuth and GitHub OAuth App registrations.

## Apply

Copy the two example files without committing the populated copies:

```sh
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
tofu init -backend-config=backend.hcl
tofu plan -out=production.tfplan
tofu apply production.tfplan
```

The Cloud Run image variable accepts only a digest-pinned image. Tags are deliberately rejected. A first deployment must bootstrap the APIs, Artifact Registry, KMS key, Firebase project, and secret containers before building that image and applying the complete plan; follow [`../../docs/cloud-operations.md`](../../docs/cloud-operations.md) for the ordered sequence.

`push_delivery_enabled` is the production circuit breaker. Its normal value is `true`. Setting it to `false` leaves identity and account management available while rejecting new push sends before an event or quota record is written.

## Populate Secret Versions

OpenTofu creates secret containers but no secret versions. Add values through standard input so values do not enter shell history, plans, or state:

```sh
gcloud secrets versions add alera-database-url --data-file=-
gcloud secrets versions add alera-edge-origin-token --data-file=-
gcloud secrets versions add alera-github-oauth-client-secret --data-file=-
gcloud secrets versions add alera-google-oauth-client-secret --data-file=-
gcloud secrets versions add alera-tombstone-pepper --data-file=-
```

Use independent random values for the origin token and tombstone pepper. Never reuse an OAuth client secret.

Cloud Run references the `latest` enabled version of each secret. After changing a secret version out of band, advance the non-secret `cloud_run_revision` marker and apply OpenTofu so the service creates a revision whose instances all read the intended values. The marker is also part of the documented zero-downtime edge-token sequence.

Cloud KMS returns its public key in PEM/SPKI form. Convert the first version's raw 32-byte Ed25519 key to unpadded base64url and set `kms_public_key_b64url` before the Cloud Run apply. That value is public and may safely appear in state; the private key never leaves KMS.

## Deploy The Edge

The DNS record fails closed before the Worker exists: Cloud Run does not own the public hostname, and every supported origin route except `/healthz` also requires the private edge token. From `edge/`, add `ORIGIN_BASE_URL` and the matching `EDGE_ORIGIN_TOKEN` with `wrangler secret put`, then deploy the Worker. Wrangler owns the Worker code, route, rate-limit binding, and secret values; OpenTofu owns the proxied DNS record.

## Firebase Client Configuration

Use the app ids in `tofu output` to download `google-services.json` and `GoogleService-Info.plist`. These client configuration files identify the Firebase project and are not service-account credentials. APNs delivery still requires an Apple developer account and an APNs authentication key uploaded to Firebase.

## State And Secret Boundary

The remote state contains resource identifiers, the OAuth client ids, the selected Neon project id, public signing-key material, and the Cloud Run origin URL. It does not contain the Neon database URL, OAuth client secrets, edge tokens, tombstone pepper, Worker secrets, or service-account private keys. Restrict access to the state bucket even though those secret values are excluded.
