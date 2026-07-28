interface RateLimitBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface EdgeEnvironment {
  EDGE_BURST_LIMITER: RateLimitBinding;
  EDGE_ORIGIN_TOKEN: string;
  ORIGIN_BASE_URL: string;
}

type OriginFetch = (request: Request) => Promise<Response>;

const ALLOWED_METHODS = new Set(['GET', 'POST', 'PUT', 'DELETE']);
const SAFE_METHODS = new Set(['GET']);
const ORIGIN_HEADER = 'x-alera-origin-auth';
const PUBLIC_EXACT_PATHS = new Set(['/healthz', '/.well-known/jwks.json']);
const PUBLIC_PREFIXES = ['/v1/'];

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

export async function handleRequest(
  request: Request,
  env: EdgeEnvironment,
  fetchOrigin: OriginFetch = fetch,
): Promise<Response> {
  const configurationError = validateEnvironment(env);
  if (configurationError) return configurationError;

  const url = new URL(request.url);
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

export default {
  fetch(request: Request, env: EdgeEnvironment): Promise<Response> {
    return handleRequest(request, env);
  },
};
