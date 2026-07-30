# Alera API Edge

This Cloudflare Worker is the only supported public route to the Alera Cloud Run service. It admits `/v1/*`, `/.well-known/jwks.json`, and `/health`; applies a short mutation burst limit; removes cookies; overwrites the origin-authentication header; and proxies the request without interpreting Alera protocol payloads.

Production deployment is owned by `.github/workflows/cloud-deploy.yml`. Wrangler receives a dedicated `cloud-production` Environment token limited to `Workers Scripts: Edit` on the Leynier account and `Workers Routes: Edit` on `alera.build`. Local `wrangler deploy` is a break-glass operation.

## Local Validation

```sh
bun install
bun run check
bun test
```

## Production Secrets

Wrangler manages both runtime values so neither appears in source or OpenTofu state:

```sh
bunx wrangler secret put ORIGIN_BASE_URL
bunx wrangler secret put EDGE_ORIGIN_TOKEN
```

`ORIGIN_BASE_URL` is the generated Cloud Run `run.app` URL. `EDGE_ORIGIN_TOKEN` must match the latest version of the `alera-edge-origin-token` Google Secret Manager secret. Deploy only after both values are set:

```sh
bun run deploy
```

The backend rejects every route except `/health` unless the edge token matches. `ALERA_ALLOW_DIRECT_ORIGIN=true` is reserved for explicit local development and must never be enabled in production.
