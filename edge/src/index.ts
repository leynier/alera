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
  ORIGIN_BASE_URL: string;
  RELAY_ENABLED?: string;
  RELAY_OBJECTS?: RelayNamespace;
  RELAY_ISSUER?: string;
  RELAY_JWKS_URL?: string;
}

interface RelayClaims {
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  nbf: number;
  jti: string;
  accountId: string;
  runtimeId: string;
  clientId: string;
  role: 'runtime' | 'mobile';
  keyVersion: number;
  clientPublicKey: string;
  runtimePublicKey: string;
}

interface RelayAttachment extends RelayClaims {}

type OriginFetch = (request: Request) => Promise<Response>;
type RelayFetch = (request: Request) => Promise<Response>;

const ALLOWED_METHODS = new Set(['GET', 'POST', 'PUT', 'DELETE']);
const SAFE_METHODS = new Set(['GET']);
const ORIGIN_HEADER = 'x-alera-origin-auth';
const PUBLIC_EXACT_PATHS = new Set(['/health', '/.well-known/jwks.json']);
const PUBLIC_PREFIXES = ['/v1/'];
const RELAY_PREFIX = '/v1/relay/';
const RELAY_CONTROL_PATHS = new Set(['/v1/relay/identity', '/v1/relay/grants']);
const RELAY_AUDIENCE = 'alera-relay';
const MAX_RELAY_FRAME_BYTES = 1024 * 1024;
const MAX_RELAY_MOBILE_CONNECTIONS = 8;
const MAX_RELAY_CLIENT_ID_BYTES = 128;

function jsonError(status: number, code: string, message: string): Response {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: {
      'cache-control': 'no-store',
      'content-type': 'application/json; charset=utf-8',
    },
  });
}

function isPublicPath(pathname: string): boolean {
  return PUBLIC_EXACT_PATHS.has(pathname) || PUBLIC_PREFIXES.some((prefix) => pathname.startsWith(prefix));
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

function originRequest(request: Request, env: EdgeEnvironment, incomingUrl: URL): Request {
  const originUrl = new URL(env.ORIGIN_BASE_URL);
  originUrl.pathname = incomingUrl.pathname;
  originUrl.search = incomingUrl.search;

  const headers = new Headers(request.headers);
  headers.delete('cookie');
  headers.set(ORIGIN_HEADER, env.EDGE_ORIGIN_TOKEN);
  headers.set('x-forwarded-host', incomingUrl.host);
  headers.set('x-forwarded-proto', 'https');

  return new Request(originUrl, {
    body: SAFE_METHODS.has(request.method) ? undefined : request.body,
    headers,
    method: request.method,
    redirect: 'manual',
  });
}

function secureResponse(response: Response): Response {
  const headers = new Headers(response.headers);
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

function base64UrlBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function decodeJsonPart<T>(value: string): T {
  return JSON.parse(new TextDecoder().decode(base64UrlBytes(value))) as T;
}

function bearerToken(request: Request): string | null {
  const value = request.headers.get('authorization');
  return value?.startsWith('Bearer ') ? value.slice('Bearer '.length) : null;
}

async function verifyRelayGrant(
  token: string,
  env: EdgeEnvironment,
  fetcher: RelayFetch = (request) => fetch(request),
): Promise<RelayAttachment | null> {
  const parts = token.split('.');
  if (parts.length !== 3 || !env.RELAY_JWKS_URL) return null;
  let header: { alg?: string; typ?: string; kid?: string };
  let claims: RelayClaims;
  try {
    header = decodeJsonPart(parts[0]);
    claims = decodeJsonPart(parts[1]);
  } catch {
    return null;
  }
  let publicKeyBytes: Uint8Array;
  let runtimeKeyBytes: Uint8Array;
  try {
    publicKeyBytes = base64UrlBytes(claims.clientPublicKey);
    runtimeKeyBytes = base64UrlBytes(claims.runtimePublicKey);
  } catch {
    return null;
  }
  if (
    header.alg !== 'EdDSA' ||
    header.typ !== 'relay+jwt' ||
    !header.kid ||
    claims.aud !== RELAY_AUDIENCE ||
    claims.iss !== (env.RELAY_ISSUER ?? '') ||
    claims.exp <= Math.floor(Date.now() / 1000) ||
    claims.nbf > Math.floor(Date.now() / 1000) + 30 ||
    claims.iat > Math.floor(Date.now() / 1000) + 30 ||
    !claims.jti ||
    !claims.accountId ||
    !claims.runtimeId ||
    !claims.clientId ||
    !['runtime', 'mobile'].includes(claims.role) ||
    !Number.isInteger(claims.keyVersion) ||
    claims.keyVersion <= 0 ||
    publicKeyBytes.byteLength !== 32 ||
    runtimeKeyBytes.byteLength !== 32
  ) {
    return null;
  }

  let jwks: {
    keys?: Array<{
      kid?: string;
      kty?: string;
      crv?: string;
      x?: string;
      alg?: string;
    }>;
  };
  try {
    const response = await fetcher(
      new Request(env.RELAY_JWKS_URL, {
        headers: { accept: 'application/json' },
      }),
    );
    if (!response.ok) return null;
    jwks = (await response.json()) as typeof jwks;
  } catch {
    return null;
  }
  const key = jwks.keys?.find(
    (candidate) =>
      candidate.kid === header.kid &&
      candidate.kty === 'OKP' &&
      candidate.crv === 'Ed25519' &&
      candidate.alg === 'EdDSA' &&
      typeof candidate.x === 'string',
  );
  if (!key?.x) return null;
  try {
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      base64UrlBytes(key.x),
      { name: 'Ed25519', namedCurve: 'Ed25519' },
      false,
      ['verify'],
    );
    const valid = await crypto.subtle.verify(
      { name: 'Ed25519' },
      cryptoKey,
      base64UrlBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
    return valid ? claims : null;
  } catch {
    return null;
  }
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

function isWebSocketUpgrade(request: Request): boolean {
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
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(message.subarray(2, idLength + 2));
  } catch {
    return null;
  }
}

function relayDisconnectFrame(clientId: string): Uint8Array {
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
  const claims = await verifyRelayGrant(token, env, fetcher);
  if (!claims || claims.runtimeId !== runtimeId) {
    return jsonError(403, 'invalid_relay_grant', 'The relay grant is invalid or out of scope.');
  }
  const forwarded = new Request(request, {
    headers: new Headers({
      upgrade: 'websocket',
      'x-alera-relay-claims': encodedClaims(claims),
    }),
  });
  const objectId = env.RELAY_OBJECTS.idFromName(runtimeId);
  return env.RELAY_OBJECTS.get(objectId).fetch(forwarded);
}

export async function handleRequest(
  request: Request,
  env: EdgeEnvironment,
  fetchOrigin: OriginFetch = fetch,
  fetchRelay?: RelayFetch,
): Promise<Response> {
  const url = new URL(request.url);
  if (
    env.RELAY_ENABLED === 'true' &&
    url.pathname.startsWith(RELAY_PREFIX) &&
    !RELAY_CONTROL_PATHS.has(url.pathname)
  ) {
    const fetchJwks =
      fetchRelay ??
      ((jwksRequest: Request) => {
        const jwksUrl = new URL(jwksRequest.url);
        return fetchOrigin(originRequest(jwksRequest, env, jwksUrl));
      });
    return handleRelayRequest(request, env, fetchJwks);
  }
  const configurationError = validateEnvironment(env);
  if (configurationError) return configurationError;

  if (!isPublicPath(url.pathname)) {
    return jsonError(404, 'route_not_found', 'The requested API route does not exist.');
  }
  if (!ALLOWED_METHODS.has(request.method)) {
    return jsonError(405, 'method_not_allowed', 'The request method is not allowed.');
  }

  if (!SAFE_METHODS.has(request.method)) {
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
    return secureResponse(response);
  } catch {
    return jsonError(502, 'origin_unavailable', 'The Alera service is temporarily unavailable.');
  }
}

export class RuntimeRelayDurableObject {
  private readonly ctx: DurableObjectState;

  constructor(ctx: DurableObjectState) {
    this.ctx = ctx;
  }

  async fetch(request: Request): Promise<Response> {
    if (!isWebSocketUpgrade(request)) {
      return jsonError(426, 'websocket_required', 'The relay requires a WebSocket connection.');
    }
    const encoded = request.headers.get('x-alera-relay-claims');
    if (!encoded) return jsonError(403, 'missing_relay_claims', 'Relay claims are missing.');
    let attachment: RelayAttachment;
    try {
      const bytes = base64UrlBytes(encoded);
      attachment = JSON.parse(new TextDecoder().decode(bytes)) as RelayAttachment;
    } catch {
      return jsonError(403, 'invalid_relay_claims', 'Relay claims are invalid.');
    }
    const webSocketPair = new WebSocketPair();
    const [client, server] = Object.values(webSocketPair) as [WebSocket, WebSocket];
    const peers = this.ctx.getWebSockets();
    const peerAttachments = peers.map((peer) => peer.deserializeAttachment() as RelayAttachment);
    const replacingDuplicate = peerAttachments.some(
      (peer) => peer.role === attachment.role && peer.clientId === attachment.clientId,
    );
    for (const peer of peers) {
      const peerAttachment = peer.deserializeAttachment() as RelayAttachment;
      if (peerAttachment.role === attachment.role && peerAttachment.clientId === attachment.clientId) {
        if (peerAttachment.role === 'mobile') {
          this.notifyRuntimeOfMobileDisconnect(peerAttachment);
        }
        peer.close(
          4001,
          attachment.role === 'runtime' ? 'replaced by a newer runtime' : 'replaced by a newer mobile connection',
        );
      }
    }
    if (
      attachment.role === 'mobile' &&
      peerAttachments.filter((peer) => peer.role === 'mobile').length >= MAX_RELAY_MOBILE_CONNECTIONS &&
      !replacingDuplicate
    ) {
      return jsonError(429, 'relay_mobile_limit', 'This runtime has reached its mobile connection limit.');
    }
    this.ctx.acceptWebSocket(server, [attachment.role, attachment.clientId]);
    server.serializeAttachment(attachment);
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(socket: WebSocket, message: ArrayBuffer | string): void {
    const bytes = typeof message === 'string' ? new TextEncoder().encode(message) : new Uint8Array(message);
    if (bytes.byteLength > MAX_RELAY_FRAME_BYTES) {
      socket.close(1009, 'relay frame too large');
      return;
    }
    const sender = socket.deserializeAttachment() as RelayAttachment;
    const now = Math.floor(Date.now() / 1000);
    if (sender.exp <= now) {
      socket.close(4003, 'relay grant expired');
      return;
    }
    const clientId = relayFrameClientId(bytes);
    if (!clientId) {
      socket.close(1007, 'invalid relay frame');
      return;
    }
    if (sender.role === 'mobile' && sender.clientId !== clientId) {
      socket.close(1008, 'relay client id mismatch');
      return;
    }
    for (const peer of this.ctx.getWebSockets()) {
      if (peer === socket) continue;
      const target = peer.deserializeAttachment() as RelayAttachment;
      if (target.exp <= now) {
        peer.close(4003, 'relay grant expired');
        continue;
      }
      if (
        sender.role === target.role ||
        sender.accountId !== target.accountId ||
        sender.runtimeId !== target.runtimeId ||
        (sender.role === 'runtime' && target.clientId !== clientId)
      ) {
        continue;
      }
      try {
        peer.send(bytes);
      } catch {
        peer.close(1011, 'relay forwarding failed');
      }
    }
  }

  webSocketClose(socket: WebSocket): void {
    this.notifyRuntimeOfMobileDisconnect(socket.deserializeAttachment() as RelayAttachment);
  }

  webSocketError(socket: WebSocket): void {
    this.notifyRuntimeOfMobileDisconnect(socket.deserializeAttachment() as RelayAttachment);
  }

  private notifyRuntimeOfMobileDisconnect(mobile: RelayAttachment): void {
    if (mobile.role !== 'mobile') return;
    const frame = relayDisconnectFrame(mobile.clientId);
    for (const peer of this.ctx.getWebSockets('runtime')) {
      const runtime = peer.deserializeAttachment() as RelayAttachment;
      if (runtime.accountId !== mobile.accountId || runtime.runtimeId !== mobile.runtimeId) continue;
      try {
        peer.send(frame);
      } catch {
        peer.close(1011, 'relay forwarding failed');
      }
    }
  }
}

export default {
  fetch(request: Request, env: EdgeEnvironment): Promise<Response> {
    return handleRequest(request, env);
  },
};
