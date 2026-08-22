# Alera API Edge

This Cloudflare Worker is the only supported public route to the Alera Cloud Run service. It admits `/v1/*`, `/.well-known/jwks.json`, and `/health`; applies a short mutation burst limit; removes cookies; overwrites the origin-authentication header; and proxies the request without interpreting Alera protocol payloads. The `/v1/relay/{runtimeId}` route is the exception in transport only: it verifies a short-lived cloud grant and forwards opaque WebSocket frames to one per-runtime Durable Object.

Production deployment is owned by `.github/workflows/cloud-deploy.yml`. Wrangler receives a dedicated `cloud-production` Environment token limited to `Workers Scripts: Edit` on the Leynier account and `Workers Routes: Edit` on `alera.build`. Local `wrangler deploy` is a break-glass operation.

## Local Validation

```sh
bun install
bun run check
bun test
```

Relay checks use the WebSocket Hibernation API. Each Object accepts one runtime connection and at most eight mobile connections, forwards only between opposite roles, enforces a 1 MiB frame bound, and keeps only verified claims in WebSocket attachments. It does not use Durable Object storage, alarms, timers, outbound sockets, or payload logging. The runtime and mobile endpoints provide the E2E encryption layer; the Worker and Object never decrypt protocol content. Only the exact value `RELAY_ENABLED=true` exposes the relay route; every other value preserves the ordinary backend proxy behavior.

## Production Secrets

Wrangler manages both runtime values so neither appears in source or OpenTofu state:

```sh
bunx wrangler secret put ORIGIN_BASE_URL
bunx wrangler secret put EDGE_ORIGIN_TOKEN
```

The relay issuer and JWKS URL are non-secret Worker variables in `wrangler.jsonc`. They must match `ALERA_ISSUER` and the public cloud JWKS route. The relay WebSocket path is derived from `ALERA_RELAY_BASE_URL`; keep its host on the Worker route.

`ORIGIN_BASE_URL` is the generated Cloud Run `run.app` URL. `EDGE_ORIGIN_TOKEN` must match the latest version of the `alera-edge-origin-token` Google Secret Manager secret. Deploy only after both values are set:

```sh
bun run deploy
```

The backend rejects every route except `/health` unless the edge token matches. `ALERA_ALLOW_DIRECT_ORIGIN=true` is reserved for explicit local development and must never be enabled in production.
