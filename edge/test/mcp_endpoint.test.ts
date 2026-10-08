import { describe, expect, test } from 'bun:test';
import { handleRequest } from '../src/index';
import { loadCatalog, RUNTIME_TOOLS } from '../src/mcp/tools';
import { accessToken, json, mcpHarness, MCP_URL, ORIGIN } from './mcp_fixture';
import { environment } from './relay_fixture';

const METADATA = 'https://api.alera.build/.well-known/oauth-protected-resource/v1/mcp';

describe('MCP authorization', () => {
  test('a missing bearer gets a 401 challenge naming the resource metadata', async () => {
    const harness = await mcpHarness();
    const response = await harness.send({ jsonrpc: '2.0', id: 1, method: 'ping' }, { token: null });
    expect(response.status).toBe(401);
    expect(response.headers.get('www-authenticate')).toBe(
      `Bearer resource_metadata="${METADATA}", scope="mcp:read mcp:execute"`,
    );
    expect(response.headers.get('access-control-allow-origin')).toBe('*');
    expect(response.headers.get('access-control-expose-headers')).toContain('www-authenticate');
  });

  test('an invalid, foreign, or expired token gets invalid_token', async () => {
    const harness = await mcpHarness();
    const forged = `${harness.token.slice(0, harness.token.lastIndexOf('.'))}.${'A'.repeat(86)}`;
    const tokens = [
      forged,
      'not-a-jwt',
      await accessToken(harness.privateKey, { aud: 'alera-relay' }),
      await accessToken(harness.privateKey, { client_kind: 'runtime' }),
      await accessToken(harness.privateKey, { iss: 'https://evil.example' }),
      await accessToken(harness.privateKey, { exp: Math.floor(Date.now() / 1000) - 1 }),
      await accessToken(harness.privateKey, { nbf: Math.floor(Date.now() / 1000) + 600 }),
      await accessToken(harness.privateKey, {}, { typ: 'relay+jwt' }),
    ];
    for (const token of tokens) {
      const response = await harness.send({ jsonrpc: '2.0', id: 1, method: 'ping' }, { token });
      expect(response.status).toBe(401);
      expect(response.headers.get('www-authenticate')).toContain('error="invalid_token"');
    }
    expect(harness.originRequests).toBeEmpty();
  });

  test('a token without mcp:read is refused with insufficient_scope', async () => {
    const harness = await mcpHarness();
    const token = await accessToken(harness.privateKey, { scope: 'mcp:execute' });
    const response = await harness.send({ jsonrpc: '2.0', id: 1, method: 'ping' }, { token });
    expect(response.status).toBe(403);
    expect(response.headers.get('www-authenticate')).toContain('error="insufficient_scope"');
  });

  test('unavailable signing keys map to 503', async () => {
    const harness = await mcpHarness({ jwks: async () => new Response(null, { status: 500 }) });
    const response = await harness.send({ jsonrpc: '2.0', id: 1, method: 'ping' });
    expect(response.status).toBe(503);
  });

  test('the MCP limiter is keyed by token hash and replaces the burst limiter', async () => {
    const limited = await mcpHarness({ limiter: false });
    const response = await limited.send({ jsonrpc: '2.0', id: 1, method: 'ping' });
    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('60');
    expect(((await response.json()) as { error: { code: number } }).error.code).toBe(-32000);
    expect(limited.limiterKeys[0]).toMatch(/^mcp:[0-9a-f]{64}$/);
    expect(limited.limiterKeys[0]).not.toContain(limited.token);

    const allowed = await mcpHarness();
    expect((await allowed.send({ jsonrpc: '2.0', id: 1, method: 'ping' })).status).toBe(200);
    expect(allowed.burstCalls).toBe(0);
  });
});

describe('MCP transport', () => {
  test('initialize negotiates the protocol version', async () => {
    const harness = await mcpHarness();
    const known = await harness.rpc('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'test', version: '1' },
    });
    expect(known.result.protocolVersion).toBe('2025-06-18');
    expect(known.result.serverInfo).toMatchObject({ name: 'alera', title: 'Alera' });
    expect(typeof known.result.serverInfo.version).toBe('string');
    expect(known.result.capabilities).toEqual({ tools: { listChanged: false } });
    expect(known.result.instructions).toContain('list_runtimes');
    const unknown = await harness.rpc('initialize', { protocolVersion: '2099-01-01' });
    expect(unknown.result.protocolVersion).toBe('2025-11-25');
  });

  test('ping, notifications, client responses, and unknown methods', async () => {
    const harness = await mcpHarness();
    expect((await harness.rpc('ping')).result).toEqual({});
    const notification = await harness.send({ jsonrpc: '2.0', method: 'notifications/initialized' });
    expect(notification.status).toBe(202);
    expect(await notification.text()).toBe('');
    expect((await harness.send({ jsonrpc: '2.0', id: 3, result: {} })).status).toBe(202);
    expect((await harness.rpc('resources/list')).error.code).toBe(-32601);
  });

  test('rejects batches, malformed JSON, invalid envelopes, and oversized bodies', async () => {
    const harness = await mcpHarness();
    const batch = await harness.send([{ jsonrpc: '2.0', id: 1, method: 'ping' }]);
    expect(batch.status).toBe(400);
    expect(((await batch.json()) as any).error.code).toBe(-32600);
    const malformed = await harness.send('{');
    expect(((await malformed.json()) as any).error.code).toBe(-32700);
    const envelope = await harness.send({ id: 1, method: 'ping' });
    expect(((await envelope.json()) as any).error.code).toBe(-32600);
    const oversized = await harness.send(`{"jsonrpc":"2.0","id":1,"method":"ping","pad":"${'x'.repeat(1024 * 1024)}"}`);
    expect(oversized.status).toBe(413);
  });

  test('rejects an unsupported protocol version header after initialization', async () => {
    const harness = await mcpHarness();
    const response = await harness.send(
      { jsonrpc: '2.0', id: 1, method: 'ping' },
      { headers: { 'mcp-protocol-version': '1999-01-01' } },
    );
    expect(response.status).toBe(400);
    const supported = await harness.send(
      { jsonrpc: '2.0', id: 1, method: 'ping' },
      { headers: { 'mcp-protocol-version': '2025-03-26' } },
    );
    expect(supported.status).toBe(200);
  });

  test('GET and DELETE are 405, OPTIONS is a CORS preflight, and the switch hides the route', async () => {
    const harness = await mcpHarness();
    for (const method of ['GET', 'DELETE']) {
      const response = await handleRequest(new Request(MCP_URL, { method }), harness.env);
      expect(response.status).toBe(405);
      expect(response.headers.get('allow')).toBe('POST, OPTIONS');
    }
    const preflight = await handleRequest(new Request(MCP_URL, { method: 'OPTIONS' }), harness.env);
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get('access-control-allow-origin')).toBe('*');
    expect(preflight.headers.get('access-control-allow-headers')).toBe(
      'authorization, content-type, mcp-protocol-version, mcp-session-id',
    );
    expect(preflight.headers.get('access-control-expose-headers')).toBe('www-authenticate, mcp-session-id');
    const disabled = await handleRequest(new Request(MCP_URL, { method: 'POST' }), {
      ...harness.env,
      MCP_ENABLED: 'false',
    });
    expect(disabled.status).toBe(404);
  });
});

describe('MCP tools', () => {
  test('the bundled catalog loads and invalid catalogs are rejected', () => {
    expect(RUNTIME_TOOLS.size).toBeGreaterThan(0);
    expect(() => loadCatalog({ version: 2, tools: [] })).toThrow();
    expect(() => loadCatalog({ version: 1, tools: [{ name: 'x' }] })).toThrow();
  });

  test('tools/list adds list_runtimes and an optional runtime argument', async () => {
    const harness = await mcpHarness();
    const { result } = await harness.rpc('tools/list');
    const names = result.tools.map((tool: { name: string }) => tool.name);
    expect(names[0]).toBe('list_runtimes');
    for (const tool of result.tools.slice(1)) {
      expect(Object.keys(tool).sort()).toEqual(['annotations', 'description', 'inputSchema', 'name', 'title']);
      expect(tool.inputSchema.properties.runtime.type).toBe('string');
      expect(tool.inputSchema.required ?? []).not.toContain('runtime');
    }
  });

  test('list_runtimes forwards the client token to the gateway', async () => {
    const harness = await mcpHarness();
    const { result } = await harness.rpc('tools/call', { name: 'list_runtimes', arguments: {} });
    expect(result.structuredContent.runtimes[0].name).toBe('laptop');
    expect(JSON.parse(result.content[0].text)).toEqual(result.structuredContent);
    const request = harness.originRequests[0];
    expect(request.method).toBe('GET');
    expect(request.url).toBe(`${ORIGIN}/v1/mcp/runtimes`);
    expect(request.headers.get('authorization')).toBe(`Bearer ${harness.token}`);
    expect(request.headers.get('x-alera-origin-auth')).toBe('edge-secret');
  });

  test('a runtime tool resolves a grant, calls the runtime object, and records the outcome', async () => {
    const harness = await mcpHarness();
    const { result } = await harness.rpc('tools/call', {
      name: 'write_terminal',
      arguments: { runtime: 'Laptop', tab: 't1', text: 'ls' },
    });
    expect(result).toEqual({
      content: [{ type: 'text', text: 'done' }],
      structuredContent: { done: true },
      isError: false,
    });
    expect(harness.originBodies[0]).toEqual({ runtime: 'Laptop', tool: 'write_terminal', access: 'execute' });
    expect(harness.relayCalls).toEqual([
      {
        runtimeId: 'runtime-1',
        body: {
          callId: 'call-1',
          grant: 'call-grant',
          tool: 'write_terminal',
          arguments: { tab: 't1', text: 'ls' },
          timeoutMs: 30000,
        },
      },
    ]);
    await Promise.all(harness.waited);
    expect(harness.originRequests[1].url).toBe(`${ORIGIN}/v1/mcp/calls/call-1/outcome`);
    expect(harness.originBodies[1]).toMatchObject({ outcome: 'ok' });
    expect(typeof (harness.originBodies[1] as { durationMs: number }).durationMs).toBe('number');
  });

  test('omitting runtime sends no runtime field', async () => {
    const harness = await mcpHarness();
    await harness.rpc('tools/call', { name: 'list_projects' });
    expect(harness.originBodies[0]).toEqual({ tool: 'list_projects', access: 'read' });
  });

  test('a read-only token cannot call execute tools', async () => {
    const harness = await mcpHarness();
    const token = await accessToken(harness.privateKey, { scope: 'mcp:read' });
    const { result } = await harness.rpc('tools/call', { name: 'write_terminal', arguments: {} }, token);
    expect(result.isError).toBeTrue();
    expect(result.content[0].text).toContain('mcp:execute');
    expect(harness.originRequests).toBeEmpty();
    const read = await harness.rpc('tools/call', { name: 'list_projects' }, token);
    expect(read.result.isError).toBeFalse();
  });

  test('unknown tools and invalid arguments are JSON-RPC errors', async () => {
    const harness = await mcpHarness();
    expect((await harness.rpc('tools/call', { name: 'rm_rf' })).error.code).toBe(-32602);
    expect((await harness.rpc('tools/call', { name: 'list_projects', arguments: [] })).error.code).toBe(-32602);
    expect((await harness.rpc('tools/call', {})).error.code).toBe(-32602);
  });

  test('gateway refusals become tool errors with the cloud code', async () => {
    const harness = await mcpHarness({
      origin: () =>
        json({ error: { code: 'runtime_required', message: 'Choose one of: laptop, desktop' } }, 409),
    });
    const { result } = await harness.rpc('tools/call', { name: 'list_projects' });
    expect(result.isError).toBeTrue();
    expect(result.content[0].text).toBe('runtime_required: Choose one of: laptop, desktop');
    expect(harness.relayCalls).toBeEmpty();
    expect(harness.waited).toBeEmpty();
  });

  test('a gateway 401 becomes an HTTP 401 challenge', async () => {
    const harness = await mcpHarness({ origin: () => json({ error: { code: 'unauthorized' } }, 401) });
    for (const name of ['list_projects', 'list_runtimes']) {
      const response = await harness.send({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name } });
      expect(response.status).toBe(401);
      expect(response.headers.get('www-authenticate')).toContain(`resource_metadata="${METADATA}"`);
    }
  });

  const relayCases: Array<[string, unknown, string, boolean]> = [
    ['offline', { ok: false, code: 'runtime_offline' }, 'runtime_offline', true],
    ['timeout', { ok: false, code: 'timeout' }, 'timeout', true],
    ['runtime error', { ok: false, code: 'invalid_grant', message: 'bad grant' }, 'failed', true],
    ['tool error', { ok: true, result: { content: [{ type: 'text', text: 'boom' }], isError: true } }, 'tool_error', true],
    ['invalid result', { ok: true, result: { content: 'nope' } }, 'failed', true],
  ];
  for (const [label, answer, outcome, isError] of relayCases) {
    test(`maps a runtime ${label} to outcome ${outcome}`, async () => {
      const harness = await mcpHarness({ relay: () => answer });
      const { result } = await harness.rpc('tools/call', { name: 'list_projects' });
      expect(result.isError).toBe(isError);
      if (label === 'runtime error') expect(result.content[0].text).toBe('invalid_grant: bad grant');
      if (label === 'offline') expect(result.content[0].text).toContain('laptop');
      await Promise.all(harness.waited);
      expect(harness.originBodies[1]).toMatchObject({ outcome });
    });
  }
});

describe('OAuth routing', () => {
  async function proxy(path: string, init: RequestInit = {}, response = new Response('ok')) {
    const seen: Request[] = [];
    const result = await handleRequest(
      new Request(`https://api.alera.build${path}`, init),
      environment(),
      async (request) => {
        seen.push(request);
        return response;
      },
    );
    return { result, seen };
  }

  for (const path of [
    '/.well-known/oauth-authorization-server',
    '/.well-known/oauth-protected-resource',
    '/.well-known/oauth-protected-resource/v1/mcp',
    '/oauth/login',
    '/device',
  ]) {
    test(`proxies GET ${path}`, async () => {
      const { result, seen } = await proxy(path, { headers: { cookie: 'a=b' } });
      expect(result.status).toBe(200);
      expect(seen[0].url).toBe(`${ORIGIN}${path}`);
      expect(seen[0].headers.get('cookie')).toBeNull();
      expect(seen[0].headers.get('x-alera-origin-auth')).toBe('edge-secret');
    });
  }

  test('moves callback and device query strings into a POST body for the origin', async () => {
    for (const path of [
      '/oauth/authorize?client_id=c&state=client-state',
      '/oauth/callback?code=provider-code&state=s1',
      '/device?user_code=ABCD-EFGH',
    ]) {
      const { result, seen } = await proxy(path);
      expect(result.status).toBe(200);
      const [pathname, query] = path.split('?');
      expect(seen[0].url).toBe(`${ORIGIN}${pathname}`);
      expect(seen[0].method).toBe('POST');
      expect(seen[0].headers.get('content-type')).toBe('application/x-www-form-urlencoded');
      expect(await seen[0].text()).toBe(query);
    }
    const { seen } = await proxy('/device');
    expect(seen[0].method).toBe('GET');
  });

  test('passes a consent redirect through unchanged', async () => {
    const location = 'http://127.0.0.1:5555/cb?code=abc&state=s&iss=https%3A%2F%2Fapi.alera.build';
    const { result, seen } = await proxy(
      '/oauth/consent',
      { method: 'POST', body: 'approve=1', headers: { 'content-type': 'application/x-www-form-urlencoded' } },
      new Response(null, { status: 302, headers: { location } }),
    );
    expect(seen[0].redirect).toBe('manual');
    expect(result.status).toBe(302);
    expect(result.headers.get('location')).toBe(location);
  });

  test('keeps HTML pages framed by DENY', async () => {
    const { result } = await proxy(
      '/oauth/authorize',
      {},
      new Response('<html></html>', { headers: { 'content-type': 'text/html; charset=utf-8' } }),
    );
    expect(result.headers.get('content-type')).toBe('text/html; charset=utf-8');
    expect(result.headers.get('x-frame-options')).toBe('DENY');
  });

  test('adds CORS headers to metadata and token responses', async () => {
    for (const path of ['/.well-known/oauth-authorization-server', '/oauth/token']) {
      const { result } = await proxy(path, path.startsWith('/oauth') ? { method: 'POST' } : {});
      expect(result.headers.get('access-control-allow-origin')).toBe('*');
    }
    const { result } = await proxy('/v1/account');
    expect(result.headers.get('access-control-allow-origin')).toBeNull();
  });

  test('answers CORS preflight only on public OAuth and metadata routes', async () => {
    for (const path of ['/.well-known/oauth-authorization-server', '/oauth/token', '/oauth/register', '/oauth/revoke']) {
      const { result, seen } = await proxy(path, { method: 'OPTIONS' });
      expect(result.status).toBe(204);
      expect(result.headers.get('access-control-allow-origin')).toBe('*');
      expect(seen).toBeEmpty();
    }
    expect((await proxy('/oauth/consent', { method: 'OPTIONS' })).result.status).toBe(405);
  });

  test('sign-in calls use their own limiters instead of the address burst limiter', async () => {
    const keys: string[] = [];
    const limiter = (success: boolean) => ({
      async limit({ key }: { key: string }) {
        keys.push(key);
        return { success };
      },
    });
    const env = {
      ...environment(),
      EDGE_BURST_LIMITER: limiter(false),
      OAUTH_LIMITER: limiter(true),
      BROWSER_LIMITER: limiter(false),
    };
    const send = (path: string, init: RequestInit = {}) =>
      handleRequest(
        new Request(`https://api.alera.build${path}`, {
          ...init,
          headers: { 'cf-connecting-ip': '203.0.113.9', ...(init.headers ?? {}) },
        }),
        env,
        async () => new Response('ok'),
      );
    for (const path of ['/oauth/token', '/oauth/register', '/oauth/revoke', '/v1/auth/device/token']) {
      expect((await send(path, { method: 'POST' })).status).toBe(200);
    }
    expect(keys).toContain('address:203.0.113.9:/v1/auth/device/token');
    const limited = await send('/device?user_code=ABCD-EFGH');
    expect(limited.status).toBe(429);
    expect(limited.headers.get('retry-after')).toBe('60');
    env.OAUTH_LIMITER = limiter(false);
    const token = await send('/oauth/token', { method: 'POST' });
    expect(token.status).toBe(429);
    expect(token.headers.get('access-control-allow-origin')).toBe('*');
    expect((await send('/oauth/authorize?client_id=x')).status).toBe(429);
    expect((await send('/v1/account', { method: 'DELETE' })).status).toBe(429);
  });

  test('keeps gateway call grants off the public route', async () => {
    for (const path of ['/v1/mcp/calls', '/v1/mcp/calls/call-1/outcome']) {
      const { result, seen } = await proxy(path, { method: 'POST' });
      expect(result.status).toBe(404);
      expect(seen).toBeEmpty();
    }
    expect((await proxy('/v1/mcp/grants')).result.status).toBe(200);
  });
});
