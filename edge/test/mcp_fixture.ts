import { expect } from 'bun:test';
import { handleRequest, type EdgeEnvironment } from '../src/index';
import { base64Url, environment, relayJwks } from './relay_fixture';

export const MCP_URL = 'https://api.alera.build/v1/mcp';
export const ORIGIN = 'https://alera-cloud.example.run.app';

export async function signingPair() {
  const keyPair = (await crypto.subtle.generateKey({ name: 'Ed25519', namedCurve: 'Ed25519' }, true, [
    'sign',
    'verify',
  ])) as CryptoKeyPair;
  const publicJwk = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JsonWebKey;
  return { privateKey: keyPair.privateKey, publicJwk };
}

export async function accessToken(
  privateKey: CryptoKey,
  overrides: Record<string, unknown> = {},
  header: Record<string, unknown> = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encodedHeader = base64Url(JSON.stringify({ alg: 'EdDSA', typ: 'at+jwt', kid: 'key-1', ...header }));
  const claims = base64Url(
    JSON.stringify({
      iss: 'https://api.alera.build',
      sub: 'account-1',
      aud: MCP_URL,
      exp: now + 900,
      iat: now,
      nbf: now,
      jti: 'token-1',
      sid: 'family-1',
      gid: 'grant-1',
      client_id: 'client-1',
      client_kind: 'mcp',
      auth_time: now,
      scope: 'mcp:read mcp:execute',
      ...overrides,
    }),
  );
  const input = `${encodedHeader}.${claims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'Ed25519' }, privateKey, new TextEncoder().encode(input)),
  );
  return `${input}.${base64Url(signature)}`;
}

export interface McpHarness {
  env: EdgeEnvironment;
  originRequests: Request[];
  originBodies: unknown[];
  relayCalls: Array<{ runtimeId: string; body: Record<string, unknown> }>;
  waited: Promise<unknown>[];
  limiterKeys: string[];
  burstCalls: number;
  send(body: unknown, init?: { token?: string | null; headers?: Record<string, string> }): Promise<Response>;
  rpc(method: string, params?: unknown, token?: string): Promise<Record<string, any>>;
}

type OriginHandler = (request: Request, body: unknown) => Response | Promise<Response>;
type RelayHandler = (body: Record<string, unknown>) => unknown;

export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export const defaultOrigin: OriginHandler = (request) => {
  const path = new URL(request.url).pathname;
  if (path === '/v1/mcp/runtimes') {
    return json({ runtimes: [{ id: 'runtime-1', name: 'laptop', online: true, mcpAccess: 'full' }] });
  }
  if (path === '/v1/mcp/calls') {
    return json({
      callId: 'call-1',
      runtimeId: 'runtime-1',
      runtimeName: 'laptop',
      grant: 'call-grant',
      expiresIn: 120,
    });
  }
  if (path.endsWith('/outcome')) return new Response(null, { status: 204 });
  return json({ error: { code: 'route_not_found', message: 'missing' } }, 404);
};

export const okRelay: RelayHandler = () => ({
  ok: true,
  result: { content: [{ type: 'text', text: 'done' }], structuredContent: { done: true }, isError: false },
});

export async function mcpHarness(
  options: {
    token?: string;
    origin?: OriginHandler;
    relay?: RelayHandler;
    limiter?: boolean;
    jwks?: (request: Request) => Promise<Response>;
    env?: Partial<EdgeEnvironment>;
  } = {},
): Promise<McpHarness & { token: string; privateKey: CryptoKey }> {
  const { privateKey, publicJwk } = await signingPair();
  const token = options.token ?? (await accessToken(privateKey));
  const harness: McpHarness & { token: string; privateKey: CryptoKey } = {
    token,
    privateKey,
    originRequests: [],
    originBodies: [],
    relayCalls: [],
    waited: [],
    limiterKeys: [],
    burstCalls: 0,
    env: undefined as unknown as EdgeEnvironment,
    async send(body, init = {}) {
      const headers = new Headers({ 'content-type': 'application/json', ...init.headers });
      const bearer = init.token === undefined ? token : init.token;
      if (bearer) headers.set('authorization', `Bearer ${bearer}`);
      return handleRequest(
        new Request(MCP_URL, {
          method: 'POST',
          headers,
          body: typeof body === 'string' ? body : JSON.stringify(body),
        }),
        harness.env,
        async (request) => {
          const text = request.body ? await request.text() : '';
          const parsed = text ? JSON.parse(text) : undefined;
          harness.originRequests.push(request);
          harness.originBodies.push(parsed);
          return (options.origin ?? defaultOrigin)(request, parsed);
        },
        options.jwks ?? relayJwks(publicJwk),
        { waitUntil: (promise: Promise<unknown>) => harness.waited.push(promise) },
      );
    },
    async rpc(method, params, bearer) {
      const response = await harness.send(
        { jsonrpc: '2.0', id: 7, method, ...(params === undefined ? {} : { params }) },
        { token: bearer },
      );
      return (await response.json()) as Record<string, any>;
    },
  };
  harness.env = {
    ...environment(),
    EDGE_BURST_LIMITER: {
      async limit() {
        harness.burstCalls++;
        return { success: false };
      },
    },
    MCP_ENABLED: 'true',
    MCP_RESOURCE: MCP_URL,
    MCP_LIMITER: {
      async limit({ key }) {
        harness.limiterKeys.push(key);
        return { success: options.limiter ?? true };
      },
    },
    RELAY_ISSUER: 'https://api.alera.build',
    RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
    RELAY_OBJECTS: {
      idFromName: (name: string) => ({ name }) as unknown as DurableObjectId,
      get: (id: DurableObjectId) =>
        ({
          async fetch(url: string, init: RequestInit) {
            const request = new Request(url, init);
            expect(request.url).toBe('https://relay.internal/mcp/call');
            const body = (await request.json()) as Record<string, unknown>;
            harness.relayCalls.push({ runtimeId: (id as unknown as { name: string }).name, body });
            return json((options.relay ?? okRelay)(body));
          },
        }) as unknown as DurableObjectStub,
    },
    ...options.env,
  };
  return harness;
}
