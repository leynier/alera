import { describe, expect, test } from 'bun:test';
import { handleRequest, pumpEventDeliveries } from '../src/index';
import { EVENT_DEFINITIONS } from '../src/mcp/events';
import { defaultOrigin, json, mcpHarness, ORIGIN } from './mcp_fixture';
import { environment } from './relay_fixture';

const MODERN = '2026-07-28';
const META = { 'io.modelcontextprotocol/protocolVersion': MODERN };
const SECRET = `whsec_${btoa(String.fromCharCode(...new Uint8Array(32).fill(7)))}`;
const ENABLED = { MCP_EVENTS_ENABLED: 'true' };

function modern(method: string, params: Record<string, unknown> = {}, id: number | string = 9) {
  return { jsonrpc: '2.0', id, method, params: { ...params, _meta: META } };
}

const MODERN_HEADERS = { 'mcp-protocol-version': MODERN };

function subscribeParams(overrides: Record<string, unknown> = {}) {
  return {
    name: 'inbox.reply',
    arguments: { threadId: 'thread-1', runtime: 'laptop' },
    delivery: { mode: 'webhook', url: 'https://receiver.example/cb', secret: SECRET },
    cursor: null,
    ...overrides,
  };
}

describe('MCP 2026-07-28 negotiation', () => {
  test('server/discover lists every version and hides events while the switch is off', async () => {
    const harness = await mcpHarness();
    const response = await harness.send(modern('server/discover'), { headers: MODERN_HEADERS });
    expect(response.status).toBe(200);
    const { result } = (await response.json()) as Record<string, any>;
    expect(result.resultType).toBe('complete');
    expect(result.supportedVersions).toEqual([MODERN, '2025-11-25', '2025-06-18', '2025-03-26']);
    expect(result.capabilities).toEqual({ tools: { listChanged: false } });
    expect(result.serverInfo).toMatchObject({ name: 'alera', title: 'Alera' });
    expect(result._meta['io.modelcontextprotocol/serverInfo'].name).toBe('alera');
    expect(result.instructions).toContain('list_runtimes');
    const enabled = await mcpHarness({ env: ENABLED });
    const discovered = await enabled.rpc('server/discover');
    expect(discovered.result.capabilities).toEqual({ tools: { listChanged: false }, events: {} });
  });

  test('modern results carry resultType while legacy results keep their shape', async () => {
    const harness = await mcpHarness();
    const ping = (await (await harness.send(modern('ping'), { headers: MODERN_HEADERS })).json()) as any;
    expect(ping.result).toEqual({ resultType: 'complete' });
    const tools = (await (await harness.send(modern('tools/list'))).json()) as any;
    expect(tools.result.resultType).toBe('complete');
    expect(tools.result.tools.length).toBeGreaterThan(1);
    expect((await harness.rpc('ping')).result).toEqual({});
    expect((await harness.rpc('tools/list')).result.resultType).toBeUndefined();
    const legacyInitialize = await harness.rpc('initialize', { protocolVersion: MODERN });
    expect(legacyInitialize.result.protocolVersion).toBe('2025-11-25');
  });

  test('header and body disagreements are rejected with HeaderMismatch', async () => {
    const harness = await mcpHarness();
    const cases: Array<[unknown, Record<string, string>]> = [
      [modern('ping'), { 'mcp-protocol-version': '2025-11-25' }],
      [modern('ping'), { ...MODERN_HEADERS, 'mcp-method': 'tools/list' }],
      [modern('tools/call', { name: 'list_runtimes' }), { ...MODERN_HEADERS, 'mcp-name': 'other_tool' }],
    ];
    for (const [body, headers] of cases) {
      const response = await harness.send(body, { headers });
      expect(response.status).toBe(400);
      expect(((await response.json()) as any).error.code).toBe(-32020);
    }
    const encoded = `=?base64?${btoa('list_runtimes')}?=`;
    const call = await harness.send(modern('tools/call', { name: 'list_runtimes' }), {
      headers: { ...MODERN_HEADERS, 'mcp-method': 'tools/call', 'mcp-name': encoded },
    });
    const called = (await call.json()) as any;
    expect(called.result.resultType).toBe('complete');
    expect(called.result.structuredContent.runtimes[0].name).toBe('laptop');
  });

  test('an unknown version gets UnsupportedProtocolVersionError and unknown modern methods 404', async () => {
    const harness = await mcpHarness();
    const response = await harness.send(
      { jsonrpc: '2.0', id: 1, method: 'ping', params: { _meta: { 'io.modelcontextprotocol/protocolVersion': '1900-01-01' } } },
    );
    expect(response.status).toBe(400);
    const { error } = (await response.json()) as any;
    expect(error.code).toBe(-32022);
    expect(error.data).toEqual({ supported: [MODERN, '2025-11-25', '2025-06-18', '2025-03-26'], requested: '1900-01-01' });
    const unknown = await harness.send(modern('resources/list'), { headers: MODERN_HEADERS });
    expect(unknown.status).toBe(404);
    expect(((await unknown.json()) as any).error.code).toBe(-32601);
    expect((await harness.send({ jsonrpc: '2.0', id: 1, method: 'resources/list' })).status).toBe(200);
  });
});

describe('MCP Events', () => {
  test('events methods do not exist while the switch is off', async () => {
    const harness = await mcpHarness();
    for (const method of ['events/list', 'events/subscribe', 'events/unsubscribe']) {
      const legacy = await harness.rpc(method, subscribeParams());
      expect(legacy.error.code).toBe(-32601);
      const response = await harness.send(modern(method, subscribeParams()), { headers: MODERN_HEADERS });
      expect(response.status).toBe(404);
    }
    expect(harness.originRequests).toBeEmpty();
  });

  test('events/list serves the catalog with webhook delivery and schemas', async () => {
    const harness = await mcpHarness({ env: ENABLED });
    const { result } = await harness.rpc('events/list');
    const names = result.events.map((event: { name: string }) => event.name);
    expect(names).toEqual([
      'inbox.reply',
      'inbox.question.status',
      'agent.status',
      'terminal.exit',
      'orchestration.task.state',
      'orchestration.gate.created',
      'orchestration.escalation',
      'automation.run.state',
      'workspace.start.state',
      'workspace.lifecycle',
      'pullRequest.watch',
    ]);
    for (const event of result.events) {
      expect(event.delivery).toEqual(['webhook']);
      expect(event.inputSchema.properties.runtime.type).toBe('string');
      expect(event.payloadSchema.required).toEqual(['runtimeId', 'seq']);
      for (const key of Object.keys(event.payloadSchema.properties)) {
        expect(key).not.toMatch(/prompt|body|text|output|command|subject/i);
      }
    }
    expect(EVENT_DEFINITIONS.find((event) => event.name === 'inbox.reply')?.inputSchema.properties).toHaveProperty(
      'threadId',
    );
    expect((await harness.rpc('events/list', { cursor: 'next' })).error.code).toBe(-32602);
    expect(harness.originRequests).toBeEmpty();
  });

  test('events/subscribe forwards a checked request to the cloud and returns its subscription', async () => {
    const harness = await mcpHarness({
      env: ENABLED,
      origin: (request, body) =>
        new URL(request.url).pathname === '/v1/mcp/event-subscriptions'
          ? json({ id: 'sub_1', refreshBefore: '2026-10-11T12:00:00Z', cursor: 'cursor-1', truncated: false })
          : defaultOrigin(request, body),
    });
    const { result } = await harness.rpc('events/subscribe', subscribeParams({ ttlMs: 3_600_000 }));
    expect(result).toEqual({ id: 'sub_1', refreshBefore: '2026-10-11T12:00:00Z', cursor: 'cursor-1', truncated: false });
    const request = harness.originRequests[0];
    expect(request.url).toBe(`${ORIGIN}/v1/mcp/event-subscriptions`);
    expect(request.headers.get('authorization')).toBe(`Bearer ${harness.token}`);
    expect(request.headers.get('x-alera-origin-auth')).toBe('edge-secret');
    expect(harness.originBodies[0]).toEqual({
      name: 'inbox.reply',
      arguments: { threadId: 'thread-1', runtime: 'laptop' },
      delivery: { mode: 'webhook', url: 'https://receiver.example/cb', secret: SECRET },
      cursor: null,
      ttlMs: 3_600_000,
    });
    const modernReply = (await (
      await harness.send(modern('events/subscribe', subscribeParams()), { headers: MODERN_HEADERS })
    ).json()) as any;
    expect(modernReply.result).toMatchObject({ resultType: 'complete', id: 'sub_1' });
  });

  test('invalid subscriptions are refused before reaching the cloud', async () => {
    const harness = await mcpHarness({ env: ENABLED });
    const invalid = [
      subscribeParams({ name: 'unknown.event' }),
      subscribeParams({ arguments: { prompt: 'x' } }),
      subscribeParams({ arguments: { threadId: 7 } }),
      subscribeParams({ delivery: { mode: 'sse', url: 'https://receiver.example/cb', secret: SECRET } }),
      subscribeParams({ delivery: { mode: 'webhook', url: 'https://receiver.example/cb' } }),
      subscribeParams({ ttlMs: 1.5 }),
      subscribeParams({ cursor: 12 }),
    ];
    for (const params of invalid) {
      expect((await harness.rpc('events/subscribe', params)).error.code).toBe(-32602);
    }
    expect(harness.originRequests).toBeEmpty();
  });

  test('cloud refusals map to MCP errors', async () => {
    const replies: Array<[Response, number, unknown]> = [
      [json({ error: { code: 'callback_endpoint_error', message: 'challenge_failed' } }, 422), -32015, { reason: 'challenge_failed' }],
      [json({ error: { code: 'callback_endpoint_error', message: 'odd' } }, 422), -32015, { reason: 'verification_failed' }],
      [json({ error: { code: 'runtime_not_found', message: 'No granted runtime.' } }, 404), -32602, undefined],
      [json({ error: { code: 'mcp_events_disabled', message: 'off' } }, 404), -32601, undefined],
      [json({ error: { code: 'webhooks_not_configured', message: 'no key' } }, 503), -32603, undefined],
    ];
    for (const [reply, code, data] of replies) {
      const harness = await mcpHarness({ env: ENABLED, origin: () => reply });
      const { error } = await harness.rpc('events/subscribe', subscribeParams());
      expect(error.code).toBe(code);
      expect(error.data).toEqual(data);
    }
    const revoked = await mcpHarness({ env: ENABLED, origin: () => json({ error: { code: 'session_revoked' } }, 401) });
    const response = await revoked.send({ jsonrpc: '2.0', id: 1, method: 'events/subscribe', params: subscribeParams() });
    expect(response.status).toBe(401);
    expect(response.headers.get('www-authenticate')).toContain('error="invalid_token"');
  });

  test('events/unsubscribe forwards the identity without the secret', async () => {
    const harness = await mcpHarness({ env: ENABLED, origin: () => new Response(null, { status: 204 }) });
    const params = {
      name: 'inbox.reply',
      arguments: { threadId: 'thread-1' },
      delivery: { mode: 'webhook', url: 'https://receiver.example/cb' },
    };
    expect((await harness.rpc('events/unsubscribe', params)).result).toEqual({});
    expect(new URL(harness.originRequests[0].url).pathname).toBe('/v1/mcp/event-subscriptions/unsubscribe');
    expect(harness.originBodies[0]).toEqual(params);
  });
});

describe('event routes at the edge', () => {
  test('subscription and pump routes are never forwarded from the internet', async () => {
    for (const path of [
      '/v1/mcp/event-subscriptions',
      '/v1/mcp/event-subscriptions/unsubscribe',
      '/v1/internal/event-deliveries/pump',
    ]) {
      let forwarded = false;
      const response = await handleRequest(
        new Request(`https://api.alera.build${path}`, { method: 'POST', body: '{}' }),
        environment(),
        async () => {
          forwarded = true;
          return new Response(null, { status: 204 });
        },
      );
      expect(response.status).toBe(404);
      expect(forwarded).toBeFalse();
    }
  });

  test('the cron pump calls the origin only when enabled', async () => {
    const requests: Request[] = [];
    const fetchOrigin = async (request: Request) => {
      requests.push(request);
      return json({ fannedOut: 0, claimed: 0, delivered: 0 });
    };
    expect(await pumpEventDeliveries(environment(), fetchOrigin)).toBeFalse();
    expect(requests).toBeEmpty();
    expect(await pumpEventDeliveries({ ...environment(), EVENT_DELIVERY_PUMP: 'true' }, fetchOrigin)).toBeTrue();
    expect(requests[0].method).toBe('POST');
    expect(requests[0].url).toBe(`${ORIGIN}/v1/internal/event-deliveries/pump`);
    expect(requests[0].headers.get('x-alera-origin-auth')).toBe('edge-secret');
  });
});
