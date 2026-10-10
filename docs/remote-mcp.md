# Remote MCP

Alera exposes one remote Model Context Protocol endpoint, `https://api.alera.build/v1/mcp`, protected by OAuth 2.1. Any runtime signed in to an Alera account, whether started by the desktop app or by `alera runtime start`, can opt in to MCP Control. An MCP client such as Claude, ChatGPT, Cursor, or Claude Code then lists the runtimes the user granted and runs Alera CLI operations on one of them per call.

The same tool catalog is also served locally by `alera mcp serve` over stdio, without the cloud.

## Decisions

- MCP Control is a per-runtime opt-in with four ordered levels: `off` (default), `read`, `full`, and `admin`. Each level allows everything the previous one does: read tools need `read`, execute tools need `full`, and administrative tools need `admin`. A runtime never moves to `admin` on its own; the user has to choose it. Remote Access for the phone stays a separate setting. Either one keeps the cloud link open.
- The privacy boundary differs from the mobile relay. An MCP client sends tool arguments over TLS to the edge, so the edge and the cloud gateway handle tool arguments and results in plaintext while forwarding them. Neither stores them. The audit log keeps metadata only: tool name, runtime, client, time, outcome, and duration. Terminal traffic between a phone and a runtime remains end-to-end encrypted and unchanged.
- The Rust cloud service is the only authorization server. It adds standard OAuth endpoints, Dynamic Client Registration, Client ID Metadata Documents, a consent page, and a device authorization flow for headless runtimes. Google and GitHub remain the identity providers.
- The MCP endpoint lives in the edge Worker, because Cloud Run requests time out after 30 seconds and the runtime socket already lives in the relay Durable Object. The edge is stateless: it builds no MCP session and keeps nothing between requests.
- The runtime is the source of the tool catalog. Each tool maps to one typed `alera` CLI invocation with `--json`, so the MCP tools keep the CLI's exact semantics. The edge serves a generated copy of the catalog and adds the `runtime` argument.
- Every routed call carries a short-lived call grant signed by the cloud for one runtime, account, tool, and call id. The runtime verifies it against the published JWKS and refuses replays before running anything, so a frame without such a grant cannot drive a runtime. The edge stays inside the trust boundary: it serves the JWKS and forwards the arguments, which the grant does not cover.
- A call names its runtime with `runtime` (name or id). When the grant reaches exactly one connected runtime, `runtime` may be omitted. Nothing is remembered between calls, so concurrent conversations cannot move each other.
- The consent page grants a list of runtimes, or every runtime including future ones, plus scopes. `mcp:read` is always granted and `mcp:execute` is checked by default. `mcp:admin` is offered only when the client requests it, behind an "Allow administrative tools" box that starts unchecked, and it is granted only together with `mcp:execute`. A tool needs both barriers: the scope of its class on the grant and a high enough MCP Control level on the runtime. Existing grants keep the scopes they were given.
- Runtime names are chosen by the user, unique per account (case-insensitive) when set explicitly, and sent again on every sign-in so the cloud never reverts to the host name. Renaming needs a signed-in account so the cloud can reserve the name. Host-name defaults, or a name carried into another account, can still repeat; name-based calls then fail with `runtime_ambiguous` and list the ids.
- Long operations are bounded. Waiting tools accept at most 50 seconds because hosted MCP clients abandon HTTP calls after about a minute; the agent polls again.

## Architecture

```text
MCP client --OAuth 2.1 (PKCE, DCR or CIMD, resource=/v1/mcp)--> Cloud Run authorization server
   |
   | POST /v1/mcp (JSON-RPC, Bearer access token)
   v
Edge Worker --GET /v1/mcp/runtimes, POST /v1/mcp/calls--> Cloud Run (grant check, audit, call grant)
   |
   | Durable Object fetch /mcp/call
   v
RuntimeRelayDurableObject(runtime) --"~mcp" frame--> runtime host --verifies call grant--> alera <command> --json
```

## Authorization Server

The issuer is `ALERA_ISSUER` (`https://api.alera.build`). The protected resource is `ALERA_MCP_RESOURCE` (default `{ALERA_PUBLIC_BASE_URL}/v1/mcp`).

| Endpoint | Purpose |
| --- | --- |
| `GET /.well-known/oauth-authorization-server` | RFC 8414 metadata, including `client_id_metadata_document_supported` and `authorization_response_iss_parameter_supported` |
| `GET /.well-known/oauth-protected-resource` and `/.well-known/oauth-protected-resource/v1/mcp` | RFC 9728 metadata for the MCP resource |
| `POST /oauth/register` | RFC 7591 registration of public clients (`token_endpoint_auth_method: none`) |
| `GET /oauth/authorize` | Validates the request and shows the sign-in page |
| `GET /oauth/login` | Starts the Google or GitHub leg for a pending authorization or device request |
| `GET /oauth/callback` | Provider callback; shows the consent page |
| `POST /oauth/consent` | Approves or denies; redirects to the client with `code`, `state`, and `iss` |
| `POST /oauth/token` | `authorization_code` and `refresh_token` grants; clients authenticate with `none` (PKCE only) or `private_key_jwt` |
| `POST /oauth/revoke` | RFC 7009 revocation; no client authentication, because holding the token is enough to revoke it |
| `GET /device` | Device sign-in page for headless runtimes (`?user_code=` jumps past code entry) |

Rules:

- PKCE S256 is mandatory. Authorization codes are single-use, stored as hashes, and expire after five minutes. Replaying a code revokes the grant.
- Redirect URIs must match a registered value exactly. Allowed forms: `https`, loopback `http` (`127.0.0.1`, `localhost`, `[::1]`, any port), reverse-domain private-use schemes (RFC 8252), and the known client schemes `cursor`, `vscode`, `vscode-insiders`, `windsurf`, `zed`, and `kiro`. Other schemes, such as OS handlers, are refused.
- Every client registered itself, so any error in an authorization request renders a page instead of redirecting; only the user's Allow or Deny returns to the client.
- The consent page names the publisher of a metadata-document client, warns when its redirect host differs, and marks dynamically registered clients as unverified, because client names are self-asserted.
- No log may hold an authorization code, state, or user code. The edge forwards the query of `/oauth/authorize`, `/oauth/callback`, and `/device` to the origin as a form body, so Cloud Run request logs record only the path; the cloud's own request spans record only the path; and the Worker runs with invocation logs off, because they record full URLs.
- The edge limits sign-in traffic by address with dedicated limiters: `OAUTH_LIMITER` (600 per minute) for `/oauth/token`, `/oauth/register`, `/oauth/revoke`, and `/v1/auth/device/token`, and `BROWSER_LIMITER` (30 per minute) for the sign-in, consent, and device pages, which also bounds user-code guessing.
- A `client_id` that is an `https` URL is a Client ID Metadata Document. The cloud fetches it over HTTPS only, refuses private, loopback, and link-local addresses, caps the response at 16 KiB and five seconds, and requires the document's `client_id` to equal its URL.
- Every client has exactly one token endpoint authentication method, stored in `mcp_clients.token_endpoint_auth_method`, and `POST /oauth/token` enforces that method: a `private_key_jwt` client never redeems without an assertion, and a public client that sends one is refused with `401 invalid_client`. Dynamically registered clients are always public. A metadata document client gets `private_key_jwt` when it declares that method with an `https` `jwks_uri` (and, if present, a `token_endpoint_auth_signing_alg` of `RS256`, `PS256`, or `ES256`); a client that declares no method or `none` is public; a client that declares a method Alera cannot use but lists `none` in `token_endpoint_auth_methods_supported` falls back to public (ChatGPT declares `private_key_jwt` and lists both); anything else is refused at authorization.
- A `private_key_jwt` client sends an RFC 7523 assertion (`client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer`) on both the code and the refresh grant. It must be signed with `RS256`, `PS256`, or `ES256` by a key from the client's `jwks_uri` (named by `kid`, or the only key published), carry `iss` and `sub` equal to the `client_id`, an `aud` that includes the issuer or the token endpoint URL, an `exp` at most five minutes ahead, and a `jti`. Each `jti` is accepted once per client (`mcp_client_assertions`, purged after expiry). The client is authenticated, and must be the client the code was issued to, before the code is consumed or treated as a replay, so a caller without the key cannot spend or revoke a stolen code. The `client_id` form field may be omitted; the assertion subject then names the client.
- Client JWKS are fetched with the same guards as metadata documents and cached per instance for ten minutes. Each JWKS is fetched by one request at a time and at most once a minute, failed attempts included, and requests that miss during a fetch wait for its result, so an unknown `kid` or an unreachable host cannot amplify unauthenticated token requests into fetches. The cache holds up to 1,024 URIs; when every entry is still inside its rate window, a new URI is refused until one frees up rather than evicting another URI's guard.
- Invalid `client_id` or `redirect_uri` renders an error page instead of redirecting.
- `resource` is optional; when present it must equal the MCP resource. `scope` defaults to `mcp:read mcp:execute` and never includes `mcp:admin` by default. A request that names `mcp:admin` also requests `mcp:execute`, and consent still decides whether to grant it. The metadata `scopes_supported` and the registration response `scope` list `mcp:read`, `mcp:execute`, and `mcp:admin`.
- The sign-in, consent, and device pages send `Content-Security-Policy` with `frame-ancestors 'none'` and a `form-action` that admits the client's redirect origin, because the consent form's response redirects there. The edge removes cookies, so the flow carries a single-use consent token in the form instead.
- Access tokens are Ed25519 JWTs (`typ: at+jwt`) valid for 15 minutes with `aud` equal to the MCP resource, `client_kind: mcp`, `client_id` equal to the OAuth client id, `gid` equal to the grant id, `sid` equal to the refresh family, and `scope` from the grant. They are rejected by every other cloud route because the audience differs.
- Refresh tokens reuse the rotating refresh families (`client_kind = 'mcp'`, `client_id = grant id`). Revoking a grant revokes its families, and `POST /oauth/revoke` with any token of a grant revokes the whole grant, because each grant has one session.
- OAuth endpoints use the standard snake_case field names and `{ error, error_description }` errors; every other route keeps camelCase and `{ error: { code, message } }`.
- Unknown scopes such as `offline_access` are ignored, and `mcp:read` is always granted. A token request may omit `redirect_uri`; when present it must match.
- `ALERA_MCP_ENABLED=false` removes the metadata, registration, authorize, token, revoke, and gateway routes. Device sign-in, grant listing, and runtime naming keep working.
- The web login uses `{ALERA_PUBLIC_BASE_URL}/oauth/callback`. Each provider needs a client that admits that redirect. Google desktop clients only accept loopback redirects, so production sets a separate Google web client (`ALERA_WEB_GOOGLE_CLIENT_ID` from `web_google_oauth_client_id`, `ALERA_WEB_GOOGLE_CLIENT_SECRET` from the `alera-web-google-oauth-client-secret` secret). A GitHub OAuth App accepts several redirect URIs, so production reuses the desktop app with that callback added and leaves `ALERA_WEB_GITHUB_CLIENT_ID` and `ALERA_WEB_GITHUB_CLIENT_SECRET` unset. Without web credentials a provider reuses the native client.

### Device Authorization

Headless runtimes (an SSH box without a browser) sign in with a device flow:

1. A runtime that still holds an active session cannot start a device sign-in (`409 runtime_already_signed_in`), because the request is unauthenticated and runtime ids are not secret. The confirmation page warns when the code would reconnect an existing runtime.
2. `POST /v1/auth/device` with `{ "clientId": "<runtime id>", "clientKind": "runtime", "deviceName": "<name>" }` returns `{ deviceCode, userCode, verificationUri, verificationUriComplete, expiresIn: 600, interval: 5 }`. The user code looks like `ABCD-EFGH`.
3. The user opens the verification URI on any device, signs in with Google or GitHub, and confirms the runtime name shown on the page. The confirmation posts to `/oauth/consent` with a `device` field.
4. The runtime polls `POST /v1/auth/device/token` with `{ "deviceCode" }`. Pending polls fail with `authorization_pending`, too-fast polls with `slow_down`, expiry or reuse with `expired_token`, an unknown code with `invalid_device_code`, and denial with `access_denied`. Approval returns the normal token envelope once. The runtime treats an edge `429` like `slow_down`.

## Account And Runtime APIs

These use the existing runtime and mobile access tokens.

| Endpoint | Caller | Result |
| --- | --- | --- |
| `GET /v1/mcp/grants` | runtime or mobile | `{ grants: [{ id, clientId, clientName, redirectHost, scopes, allRuntimes, runtimeIds, createdAt, lastUsedAt }] }` |
| `DELETE /v1/mcp/grants/{id}` | runtime or mobile | Revokes the grant and its refresh families; `204` |
| `PUT /v1/runtime/name` | the runtime itself | `{ name }` (1-64 characters, unique per account ignoring case) returns `{ id, name }`; `409 runtime_name_taken` |
| `PUT /v1/runtime/capabilities` | the runtime itself | `{ mcpAccess, mobileAccess }` returns `204`. Sent when MCP Control changes, because a runtime that turns both features off stops requesting relay grants |
| `POST /v1/relay/grants` | runtime | Adds optional `mcpAccess` (`off`, `read`, `full`, `admin`; absent means `off`) and `mobileAccess` (absent means `true`). The cloud stores both on the runtime row and copies them into the runtime's relay grant claims |
| `GET /v1/mobile/runtimes` | mobile | Excludes runtimes whose last grant reported `mobileAccess: false` |

## Gateway APIs

The edge calls these with the MCP client's own access token.

The edge returns `404` for `/v1/mcp/calls` and everything under it on the public route, so only the edge itself can obtain call grants.

- `GET /v1/mcp/runtimes` returns `{ runtimes: [{ id, name, online, mcpAccess, lastSeenAt }] }` for the runtimes the grant reaches. `online` means the runtime requested a relay grant in the last active window and its last report had MCP Control on. A runtime that stops without reporting stays listed as online until that window passes; calls to it fail fast with `runtime_offline`.
- `POST /v1/mcp/calls` with `{ runtime?, tool, access }` resolves the runtime and records the call:
  - `runtime` matches an id exactly or a name ignoring case. Unknown, ungranted, and transferred runtimes all fail with `404 runtime_not_found`. A name shared by several runtimes fails with `409 runtime_ambiguous`.
  - Without `runtime`, exactly one connected runtime is chosen; none fails with `404 no_runtime_available`, several with `409 runtime_required`. The error message lists the candidate names.
  - `access` is `read`, `execute`, or `admin`. `execute` needs the `mcp:execute` scope and `admin` needs the `mcp:admin` scope (`403 insufficient_scope`; for `admin` the message asks the user to reconnect and allow administrative tools). A runtime reporting `off` fails with `409 runtime_mcp_disabled`; `read` refuses execute tools with `403 runtime_read_only`; any level below `admin` refuses administrative tools with `403 runtime_not_admin`.
  - The response is `{ callId, runtimeId, runtimeName, grant, expiresIn }`. `grant` is an Ed25519 JWT with `typ: mcp-call+jwt`, `aud: alera-runtime-mcp`, a 120-second lifetime, `jti` equal to the call id, and claims `accountId`, `runtimeId`, `grantId`, `clientId`, `clientName`, `tool`, and `access` (`read`, `execute`, or `admin`).
- `POST /v1/mcp/calls/{id}/outcome` with `{ outcome, durationMs }` completes the audit row once and returns `204`; a second outcome returns `409 call_already_completed`. Outcomes are `ok`, `tool_error`, `runtime_offline`, `timeout`, and `failed`.
- Missing or invalid bearers return `401` (`missing_bearer`, `invalid_token`); a revoked grant or session returns `401 session_revoked` or `invalid_session`, which the edge turns into a `401` with `WWW-Authenticate`.

The audit row (`mcp_calls`) is written before the runtime is contacted. A missing outcome never causes a retry. Rows are deleted after 30 days.

## Edge MCP Endpoint

`/v1/mcp` implements stateless Streamable HTTP:

- `POST` accepts one JSON-RPC message and answers with `application/json`. Notifications return `202`. `GET` and `DELETE` return `405` because the server keeps no sessions or streams. `OPTIONS` answers CORS preflight.
- Supported protocol versions: `2025-11-25`, `2025-06-18`, and `2025-03-26`. An unknown requested version gets the newest supported one.
- Methods: `initialize`, `ping`, `tools/list`, and `tools/call`. Anything else returns `-32601`.
- A missing or invalid bearer returns `401` with `WWW-Authenticate: Bearer resource_metadata="<resource metadata URL>", scope="mcp:read mcp:execute mcp:admin"`. A token without `mcp:execute` calling an execute tool, or without `mcp:admin` calling an administrative tool, gets a tool error naming the missing scope without contacting the cloud.
- `tools/list` serves `edge/src/mcp/tool_catalog.json` plus the gateway tool `list_runtimes`. Each runtime tool gains an optional `runtime` string argument.
- Calls are limited per token by the `MCP_LIMITER` binding.
- `tools/call` asks the cloud for a call grant, then calls the runtime's Durable Object at `/mcp/call` with `{ callId, grant, tool, arguments, timeoutMs }`. The object answers `{ ok: true, result }` or `{ ok: false, code, message }`. The edge records the outcome with `waitUntil`.

## Runtime Link Frames

MCP traffic shares the runtime's existing relay WebSocket. A frame uses the normal relay wire layout (two-byte client id length, client id, payload) with the reserved client id `~mcp` and a UTF-8 JSON payload. Mobile client ids may not start with `~`.

- Durable Object to runtime: `{ "type": "mcp.call", "id", "grant", "tool", "arguments", "timeoutMs" }` and `{ "type": "mcp.cancel", "id" }`.
- Runtime to Durable Object: `{ "type": "mcp.result", "id", "result": { "content", "structuredContent"?, "isError" } }` or `{ "type": "mcp.result", "id", "error": { "code", "message" } }`.
- A single frame is at most 1 MiB; the runtime truncates command output to stay under it, and answers a call frame it cannot read with an `invalid_call` error instead of leaving the caller waiting.
- The object only routes to a runtime socket whose relay grant carries `mcpAccess` `read`, `full`, or `admin`, rejects pending calls when that socket closes, and never forwards `~mcp` frames to phones.
- The relay grant's `mobileAccess: false` makes the object refuse phones with `relay_runtime_unavailable`, and the runtime ignores phone handshakes while Remote Access is off.

## Runtime

- Settings live in `runtimeMetadata`: `settings.mcp.access` (`off`, `read`, `full`, `admin`) and `settings.runtime.name`.
- The relay link starts when an account is signed in and Remote Access or MCP Control is on, and restarts when either changes.
- The runtime verifies each call grant (issuer, audience, signature, expiry, runtime id, account id), checks the tool exists and that its access level is allowed by the local setting, and runs at most four calls at once.
- Each tool runs the runtime's own `alera` binary with `--json` and a bounded timeout. The process inherits the runtime's environment, so it talks to the same runtime.

Host requests (local clients only; never forwarded by a satellite or accepted from a phone):

| Request | Payload | Result |
| --- | --- | --- |
| `mcp.settings.get` | none | `{ access, runtimeName, effectiveRuntimeName, accountConnected, relay }` |
| `mcp.settings.update` | `{ access?, runtimeName? }` | Same shape as `mcp.settings.get`; renames in the cloud when signed in |
| `mcp.grants.list` | none | `{ grants }` from the cloud |
| `mcp.grants.revoke` | `{ grantId }` | `{ revoked: true }` |
| `account.signIn.device.start` | none | `{ userCode, verificationUri, verificationUriComplete, expiresAt }`; completion emits `aleraAccountChanged` |

## CLI

- `alera account status`, `alera account login [--provider github|google] [--device]`, `alera account logout`
- `alera runtime rename <name>`
- `alera mcp status`, `alera mcp enable [--read-only]`, `alera mcp disable`, `alera mcp apps`, `alera mcp revoke <grant-id>`
- `alera mcp tools` prints the catalog; `alera mcp serve [--read-only]` runs the stdio server against the local runtime
- The endpoint printed by `alera mcp status` follows `ALERA_CLOUD_URL`, so a development runtime shows its local cloud

## Tool Catalog

The catalog is defined in `rust/alera-cli/src/mcp_tools/`. `edge/src/mcp/tool_catalog.json` is generated from it and a Rust test fails when they differ. Regenerate it with `ALERA_UPDATE_MCP_CATALOG=1 cargo test -p alera-cli mcp_tool_catalog_matches_edge_copy`.

Each entry has `name`, `title`, `description`, `access` (`read`, `execute`, or `admin`), `timeoutSeconds`, `inputSchema`, and `annotations`. The edge accepts catalog versions 1 and 2; version 2 is the one that may contain `admin` tools.

Tools that read terminal output drop the `dataBase64` copy of the text before returning it.

## Testing

- `cloud`: `cargo test --workspace`; with `TEST_DATABASE_URL` pointing at an isolated PostgreSQL, `-- --include-ignored` also runs the OAuth, device, and gateway contracts.
- `edge`: `bun run check` and `bun test` cover the MCP endpoint, scope checks, OAuth proxying, and the Durable Object call routing.
- `rust`: `cargo test -p alera-cli -- mcp_tools mcp_settings relay_mcp` covers the catalog, argument checks, the edge catalog copy, and call grant verification on the link.
- Local acceptance: run PostgreSQL, the cloud with GitHub endpoints pointed at a stub provider, the edge with `wrangler dev --local` and the `--var` overrides for `ORIGIN_BASE_URL`, `EDGE_ORIGIN_TOKEN`, `RELAY_ISSUER`, `RELAY_JWKS_URL`, and `MCP_RESOURCE`, and an isolated runtime with `ALERA_CLOUD_URL` at the edge. Sign the runtime in with `alera account login --device`, enable MCP Control, then drive registration, authorization, consent, token, refresh, and tool calls from any MCP client. Production still needs the web OAuth clients described above before the hosted flow can sign in.
