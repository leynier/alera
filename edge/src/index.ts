import {
  bearerToken,
  verifyRelayGrant,
  RELAY_CONTROL_PROTOCOL,
  RelayAuthorizationUnavailable,
  type RelayAttachment,
} from './relay_authorization';
import { handleMcpRequest } from './mcp/endpoint';
import { CORS_HEADERS, corsPreflight, MCP_PATH } from './mcp/protocol';
interface RateLimitBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface RelayNamespace {
  idFromName(name: string): DurableObjectId;
  get(id: DurableObjectId): DurableObjectStub;
}

export interface EdgeEnvironment {
  EDGE_BURST_LIMITER: RateLimitBinding;
  EDGE_ORIGIN_TOKEN: string;
  MCP_ENABLED?: string;
  /** OpenAI MCP Events (`events/*` and `capabilities.events`). Off unless "true". */
  MCP_EVENTS_ENABLED?: string;
  /** When "true", the cron trigger asks the origin to deliver due webhooks. */
  EVENT_DELIVERY_PUMP?: string;
  MCP_LIMITER?: RateLimitBinding;
  OAUTH_LIMITER?: RateLimitBinding;
  BROWSER_LIMITER?: RateLimitBinding;
  MCP_RESOURCE?: string;
  ORIGIN_BASE_URL: string;
  RELAY_ENABLED?: string;
  RELAY_OBJECTS?: RelayNamespace;
  RELAY_ISSUER?: string;
  RELAY_JWKS_URL?: string;
  RELAY_RENEWAL_ENABLED?: string;
}

export type OriginFetch = (request: Request) => Promise<Response>;
type RelayFetch = (request: Request) => Promise<Response>;
type WaitUntil = Pick<ExecutionContext, 'waitUntil'>;

const ALLOWED_METHODS = new Set(['GET', 'POST', 'PUT', 'DELETE']);
const SAFE_METHODS = new Set(['GET']);
const ORIGIN_HEADER = 'x-alera-origin-auth';
const PUBLIC_EXACT_PATHS = new Set([
  '/health',
  '/.well-known/jwks.json',
  '/.well-known/oauth-authorization-server',
  '/.well-known/oauth-protected-resource',
  `/.well-known/oauth-protected-resource${MCP_PATH}`,
  '/oauth/authorize',
  '/oauth/login',
  '/oauth/callback',
  '/oauth/consent',
  '/oauth/token',
  '/oauth/register',
  '/oauth/revoke',
  '/device',
]);
const PUBLIC_PREFIXES = ['/v1/'];
// Gateway calls mint runtime call grants, MCP Events subscriptions must pass the edge's
// protocol checks, and the delivery pump is internal: only the edge reaches them, through
// the origin directly.
const EDGE_ONLY_PREFIXES = ['/v1/mcp/calls', '/v1/mcp/event-subscriptions', '/v1/internal'];
const EVENT_PUMP_PATH = '/v1/internal/event-deliveries/pump';
const CORS_EXACT_PATHS = new Set(['/oauth/token', '/oauth/register', '/oauth/revoke', MCP_PATH]);
// Machine-to-machine sign-in calls carry no bearer, so the burst limiter would key
// them by address alone: a device poll every five seconds, or a hosted client
// refreshing for many users from shared addresses, would trip it.
const OAUTH_CLIENT_PATHS = new Set(['/oauth/token', '/oauth/register', '/oauth/revoke', '/v1/auth/device/token']);
// Pages a person opens. Limited even for GET because each one writes a request
// row, and the device page must not allow guessing user codes.
const BROWSER_PATHS = new Set(['/device', '/oauth/authorize', '/oauth/login', '/oauth/callback', '/oauth/consent']);
const RELAY_PREFIX = '/v1/relay/';
const RELAY_CONTROL_PATHS = new Set(['/v1/relay/identity', '/v1/relay/grants']);
const MAX_RELAY_FRAME_BYTES = 1024 * 1024;
const MAX_RELAY_CLIENT_ID_BYTES = 128;

export function jsonError(status: number, code: string, message: string): Response {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: {
      'cache-control': 'no-store',
      'content-type': 'application/json; charset=utf-8',
    },
  });
}

function isPublicPath(pathname: string): boolean {
  if (EDGE_ONLY_PREFIXES.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`))) return false;
  return PUBLIC_EXACT_PATHS.has(pathname) || PUBLIC_PREFIXES.some((prefix) => pathname.startsWith(prefix));
}

function isCorsPath(pathname: string): boolean {
  return CORS_EXACT_PATHS.has(pathname) || pathname.startsWith('/.well-known/');
}

function validateEnvironment(env: EdgeEnvironment): Response | null {
  if (!env.ORIGIN_BASE_URL || !env.EDGE_ORIGIN_TOKEN) {
    return jsonError(503, 'edge_not_configured', 'The API edge is not configured.');
  }
  return null;
}

async function requestLimitKey(request: Request, pathname: string): Promise<string> {
  const authorization = request.headers.get('authorization');
  if (authorization) {
    const bytes = new TextEncoder().encode(authorization);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const value = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
    return `authorization:${value}`;
  }

  const address = request.headers.get('cf-connecting-ip') ?? 'unknown';
  return `address:${address}:${pathname}`;
}

// Pages whose query carries a provider code, OAuth state, or a device user
// code. Cloud Run logs every request URL, so the edge moves the query into a
// POST body before it reaches the origin.
const QUERY_SECRET_PATHS = new Set(['/oauth/authorize', '/oauth/callback', '/device']);

export function originRequest(request: Request, env: EdgeEnvironment, incomingUrl: URL): Request {
  const originUrl = new URL(env.ORIGIN_BASE_URL);
  originUrl.pathname = incomingUrl.pathname;
  originUrl.search = incomingUrl.search;
  if (request.method === 'GET' && QUERY_SECRET_PATHS.has(incomingUrl.pathname) && incomingUrl.search) {
    originUrl.search = '';
    const headers = new Headers(request.headers);
    headers.delete('cookie');
    headers.set(ORIGIN_HEADER, env.EDGE_ORIGIN_TOKEN);
    headers.set('x-forwarded-host', incomingUrl.host);
    headers.set('x-forwarded-proto', 'https');
    headers.set('content-type', 'application/x-www-form-urlencoded');
    return new Request(originUrl, {
      signal: request.signal,
      body: incomingUrl.search.slice(1),
      headers,
      method: 'POST',
      redirect: 'manual',
    });
  }

  const headers = new Headers(request.headers);
  headers.delete('cookie');
  headers.set(ORIGIN_HEADER, env.EDGE_ORIGIN_TOKEN);
  headers.set('x-forwarded-host', incomingUrl.host);
  headers.set('x-forwarded-proto', 'https');

  return new Request(originUrl, {
    signal: request.signal,
    body: SAFE_METHODS.has(request.method) ? undefined : request.body,
    headers,
    method: request.method,
    redirect: 'manual',
  });
}

function secureResponse(response: Response, cors = false): Response {
  const headers = new Headers(response.headers);
  if (cors) {
    for (const name of ['access-control-allow-origin', 'access-control-expose-headers']) {
      if (!headers.has(name)) headers.set(name, CORS_HEADERS[name]);
    }
  }
  headers.set('cache-control', response.headers.get('cache-control') ?? 'no-store');
  headers.set('referrer-policy', 'no-referrer');
  headers.set('x-content-type-options', 'nosniff');
  headers.set('x-frame-options', 'DENY');
  return new Response(response.body, {
    headers,
    status: response.status,
    statusText: response.statusText,
  });
}

function relayRuntimeId(pathname: string): string | null {
  if (!pathname.startsWith(RELAY_PREFIX)) return null;
  const encoded = pathname.slice(RELAY_PREFIX.length);
  if (!encoded || encoded.includes('/')) return null;
  try {
    const runtimeId = decodeURIComponent(encoded);
    return runtimeId.length > 0 && runtimeId.length <= 128 ? runtimeId : null;
  } catch {
    return null;
  }
}

export function isWebSocketUpgrade(request: Request): boolean {
  return request.headers.get('upgrade')?.toLowerCase() === 'websocket';
}

function encodedClaims(claims: RelayAttachment): string {
  return btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(claims))))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

export function relayFrameClientId(message: Uint8Array): string | null {
  if (message.byteLength < 3) return null;
  const idLength = (message[0] << 8) | message[1];
  if (idLength === 0 || idLength > MAX_RELAY_CLIENT_ID_BYTES || message.byteLength <= idLength + 2) {
    return null;
  }
  try {
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(
      message.subarray(2, idLength + 2),
    );
  } catch {
    return null;
  }
}

export function relayDisconnectFrame(clientId: string): Uint8Array {
  const id = new TextEncoder().encode(clientId);
  return new Uint8Array([(id.length >> 8) & 0xff, id.length & 0xff, ...id]);
}

async function handleRelayRequest(
  request: Request,
  env: EdgeEnvironment,
  fetcher: RelayFetch = (relayRequest) => fetch(relayRequest),
): Promise<Response> {
  const runtimeId = relayRuntimeId(new URL(request.url).pathname);
  if (!runtimeId) return jsonError(404, 'route_not_found', 'The relay route does not exist.');
  if (request.method !== 'GET' || !isWebSocketUpgrade(request)) {
    return jsonError(426, 'websocket_required', 'The relay requires a WebSocket connection.');
  }
  if (!env.RELAY_OBJECTS || !env.RELAY_ISSUER || !env.RELAY_JWKS_URL) {
    return jsonError(503, 'relay_not_configured', 'The relay is not configured.');
  }
  const token = bearerToken(request);
  if (!token) return jsonError(401, 'missing_bearer', 'A relay grant is required.');
  let claims: RelayAttachment | null;
  try {
    claims = await verifyRelayGrant(token, env, fetcher);
  } catch (error) {
    if (error instanceof RelayAuthorizationUnavailable)
      return jsonError(
        503,
        'relay_authorization_unavailable',
        'Relay authorization is temporarily unavailable.',
      );
    throw error;
  }
  if (!claims || claims.runtimeId !== runtimeId) {
    return jsonError(403, 'invalid_relay_grant', 'The relay grant is invalid or out of scope.');
  }
  const controlProtocol =
    env.RELAY_RENEWAL_ENABLED !== 'false' &&
    request.headers
      .get('sec-websocket-protocol')
      ?.split(',')
      .some((value) => value.trim() === RELAY_CONTROL_PROTOCOL);
  const attachment = { ...claims, controlProtocol: controlProtocol === true };
  const forwarded = new Request(request, {
    headers: new Headers({
      upgrade: 'websocket',
      'x-alera-relay-claims': encodedClaims(attachment),
    }),
  });
  const objectId = env.RELAY_OBJECTS.idFromName(runtimeId);
  return env.RELAY_OBJECTS.get(objectId).fetch(forwarded);
}

export async function handleRequest(
  request: Request,
  env: EdgeEnvironment,
  // Wrapped so callers can store it as an object property: workerd throws
  // "Illegal invocation" when the global fetch is called with another `this`.
  fetchOrigin: OriginFetch = (originRequest) => fetch(originRequest),
  fetchRelay?: RelayFetch,
  ctx?: WaitUntil,
): Promise<Response> {
  const url = new URL(request.url);
  const fetchJwks =
    fetchRelay ??
    ((jwksRequest: Request) => {
      const jwksUrl = new URL(jwksRequest.url);
      return fetchOrigin(originRequest(jwksRequest, env, jwksUrl));
    });
  if (
    env.RELAY_ENABLED === 'true' &&
    url.pathname.startsWith(RELAY_PREFIX) &&
    !RELAY_CONTROL_PATHS.has(url.pathname)
  ) {
    return handleRelayRequest(request, env, fetchJwks);
  }
  const configurationError = validateEnvironment(env);
  if (configurationError) return configurationError;

  if (!isPublicPath(url.pathname)) {
    return jsonError(404, 'route_not_found', 'The requested API route does not exist.');
  }
  if (url.pathname === MCP_PATH) {
    return handleMcpRequest(request, {
      env,
      fetchOrigin,
      fetchJwks,
      waitUntil: (promise) => {
        if (ctx) ctx.waitUntil(promise);
        else promise.catch(() => undefined);
      },
    });
  }
  const cors = isCorsPath(url.pathname);
  if (request.method === 'OPTIONS' && cors) return corsPreflight('GET, POST, OPTIONS');
  if (!ALLOWED_METHODS.has(request.method)) {
    return jsonError(405, 'method_not_allowed', 'The request method is not allowed.');
  }

  const signInLimiter = OAUTH_CLIENT_PATHS.has(url.pathname)
    ? env.OAUTH_LIMITER
    : BROWSER_PATHS.has(url.pathname)
      ? env.BROWSER_LIMITER
      : undefined;
  if (signInLimiter && request.method !== 'OPTIONS') {
    const address = request.headers.get('cf-connecting-ip') ?? 'unknown';
    const result = await signInLimiter.limit({ key: `address:${address}:${url.pathname}` });
    if (!result.success) {
      const response = jsonError(429, 'edge_rate_limited', 'Too many requests. Try again shortly.');
      response.headers.set('retry-after', '60');
      // Without CORS headers a browser client sees a network error, not the 429.
      return secureResponse(response, cors);
    }
  } else if (!SAFE_METHODS.has(request.method)) {
    const key = await requestLimitKey(request, url.pathname);
    const result = await env.EDGE_BURST_LIMITER.limit({ key });
    if (!result.success) {
      const response = jsonError(429, 'edge_rate_limited', 'Too many requests. Try again shortly.');
      response.headers.set('retry-after', '60');
      return response;
    }
  }

  try {
    const response = await fetchOrigin(originRequest(request, env, url));
    return secureResponse(response, cors);
  } catch {
    return jsonError(502, 'origin_unavailable', 'The Alera service is temporarily unavailable.');
  }
}

export { RuntimeRelayDurableObject } from './runtime_relay';

/** Cron: asks the origin to fan out and deliver due webhooks while Cloud Run idles. */
export async function pumpEventDeliveries(
  env: EdgeEnvironment,
  fetchOrigin: OriginFetch = (originRequest) => fetch(originRequest),
): Promise<boolean> {
  if (env.EVENT_DELIVERY_PUMP !== 'true' || validateEnvironment(env)) return false;
  const url = new URL(EVENT_PUMP_PATH, env.ORIGIN_BASE_URL);
  const request = new Request(url, { method: 'POST', signal: AbortSignal.timeout(25000) });
  try {
    const response = await fetchOrigin(originRequest(request, env, url));
    return response.ok;
  } catch {
    return false;
  }
}

export default {
  fetch(request: Request, env: EdgeEnvironment, ctx: ExecutionContext): Promise<Response> {
    return handleRequest(request, env, undefined, undefined, ctx);
  },
  scheduled(_controller: ScheduledController, env: EdgeEnvironment, ctx: ExecutionContext): void {
    ctx.waitUntil(pumpEventDeliveries(env));
  },
};
