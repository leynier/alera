import { describe, expect, test } from 'bun:test';
import { RuntimeRelayDurableObject } from '../src/index';
import { McpRelayCalls, mcpFrame } from '../src/mcp/relay_calls';
import { verifyRelayGrant } from '../src/relay_authorization';
import { base64Url, environment, relayAttachment, relayJwks, signedRelayGrant, TestSocket } from './relay_fixture';

function mcpRuntime(mcpAccess?: 'off' | 'read' | 'full', expiresIn = 120) {
  return new TestSocket({ ...relayAttachment('runtime', 'runtime-1', expiresIn), mcpAccess });
}

function relay(sockets: TestSocket[]) {
  return new RuntimeRelayDurableObject({
    getWebSockets: () => sockets as unknown as WebSocket[],
  } as unknown as DurableObjectState);
}

function callRequest(overrides: Record<string, unknown> = {}, signal?: AbortSignal) {
  return new Request('https://relay.internal/mcp/call', {
    method: 'POST',
    body: JSON.stringify({
      callId: 'call-1',
      grant: 'call-grant',
      tool: 'list_projects',
      arguments: { all: true },
      timeoutMs: 30000,
      ...overrides,
    }),
    signal,
  });
}

function decode(frame: Uint8Array) {
  const idLength = (frame[0] << 8) | frame[1];
  return {
    clientId: new TextDecoder().decode(frame.subarray(2, 2 + idLength)),
    payload: JSON.parse(new TextDecoder().decode(frame.subarray(2 + idLength))),
  };
}

const sent = (socket: TestSocket) => socket.sent.map(decode);

async function settled(response: Promise<Response>) {
  return (await (await response).json()) as Record<string, unknown>;
}

describe('MCP relay calls', () => {
  test('sends a ~mcp call frame and settles it from the runtime result', async () => {
    const runtime = mcpRuntime('full');
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));
    const object = relay([runtime, mobile]);
    const pending = object.fetch(callRequest());
    await Bun.sleep(0);
    expect(sent(runtime)).toEqual([
      {
        clientId: '~mcp',
        payload: {
          type: 'mcp.call',
          id: 'call-1',
          grant: 'call-grant',
          tool: 'list_projects',
          arguments: { all: true },
          timeoutMs: 30000,
        },
      },
    ]);
    const result = { content: [{ type: 'text', text: 'ok' }], isError: false };
    object.webSocketMessage(
      runtime as unknown as WebSocket,
      mcpFrame({ type: 'mcp.result', id: 'call-1', result }).buffer as ArrayBuffer,
    );
    expect(await settled(pending)).toEqual({ ok: true, result });
    expect(mobile.sent).toBeEmpty();
  });

  test('passes a runtime error through and ignores results from other sockets', async () => {
    const runtime = mcpRuntime('read');
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));
    const object = relay([runtime, mobile]);
    const pending = object.fetch(callRequest());
    await Bun.sleep(0);
    const error = mcpFrame({ type: 'mcp.result', id: 'call-1', error: { code: 'invalid_grant', message: 'no' } });
    object.webSocketMessage(mobile as unknown as WebSocket, error.buffer as ArrayBuffer);
    expect(mobile.closed?.code).toBe(1008);
    object.webSocketMessage(runtime as unknown as WebSocket, error.buffer as ArrayBuffer);
    expect(await settled(pending)).toEqual({ ok: false, code: 'invalid_grant', message: 'no' });
  });

  test('an unparseable result still settles its caller when the id is readable', async () => {
    const runtime = mcpRuntime('full');
    const object = relay([runtime]);
    const pending = object.fetch(callRequest());
    await Bun.sleep(0);
    const id = new TextEncoder().encode('~mcp');
    const body = new TextEncoder().encode('{"type":"mcp.result","id":"call-1","result":{');
    const frame = new Uint8Array([0, id.length, ...id, ...body]);
    object.webSocketMessage(runtime as unknown as WebSocket, frame.buffer as ArrayBuffer);
    expect((await settled(pending)).code).toBe('invalid_result');
    expect(runtime.closed).toBeNull();
  });

  for (const access of [undefined, 'off'] as const) {
    test(`refuses runtime sockets with mcpAccess ${access ?? 'absent'}`, async () => {
      const runtime = mcpRuntime(access);
      expect((await settled(relay([runtime]).fetch(callRequest()))).code).toBe('runtime_offline');
      expect(runtime.sent).toBeEmpty();
    });
  }

  test('refuses expired runtimes and invalid call bodies', async () => {
    expect((await settled(relay([mcpRuntime('full', -1)]).fetch(callRequest()))).code).toBe('runtime_offline');
    const invalid = await relay([mcpRuntime('full')]).fetch(callRequest({ timeoutMs: 'soon' }));
    expect(invalid.status).toBe(400);
  });

  test('a runtime close rejects pending calls', async () => {
    const runtime = mcpRuntime('full');
    const object = relay([runtime]);
    const pending = object.fetch(callRequest());
    await Bun.sleep(0);
    object.webSocketClose(runtime as unknown as WebSocket);
    expect((await settled(pending)).code).toBe('runtime_offline');
  });

  test('a replaced runtime rejects its pending calls', async () => {
    const runtime = mcpRuntime('full');
    const sockets = [runtime];
    const object = relay(sockets);
    const pending = object.fetch(callRequest());
    await Bun.sleep(0);
    const upgrade = new Request('https://relay.test/v1/relay/runtime-1', {
      headers: {
        upgrade: 'websocket',
        'x-alera-relay-claims': base64Url(JSON.stringify(relayAttachment('runtime', 'runtime-1'))),
      },
    });
    // WebSocketPair does not exist under Bun; the replacement bookkeeping runs before it.
    await object.fetch(upgrade).catch(() => undefined);
    expect((await settled(pending)).code).toBe('runtime_offline');
  });

  test('a timeout settles the caller and cancels the runtime call', async () => {
    const runtime = mcpRuntime('full');
    const calls = new McpRelayCalls(() => [runtime as unknown as WebSocket], 0);
    const answer = await settled(calls.handle(callRequest({ timeoutMs: 5 })));
    expect(answer.code).toBe('timeout');
    expect(sent(runtime).map((frame) => frame.payload.type)).toEqual(['mcp.call', 'mcp.cancel']);
    expect(sent(runtime)[1].payload.id).toBe('call-1');
  });

  test('an aborted caller cancels the runtime call', async () => {
    const runtime = mcpRuntime('full');
    const calls = new McpRelayCalls(() => [runtime as unknown as WebSocket]);
    const controller = new AbortController();
    const pending = calls.handle(callRequest({}, controller.signal));
    await Bun.sleep(0);
    controller.abort();
    expect((await settled(pending)).code).toBe('cancelled');
    expect(sent(runtime)[1].payload).toEqual({ type: 'mcp.cancel', id: 'call-1' });
  });

  test('rejects a duplicate in-flight call id', async () => {
    const runtime = mcpRuntime('full');
    const calls = new McpRelayCalls(() => [runtime as unknown as WebSocket]);
    const first = calls.handle(callRequest());
    await Bun.sleep(0);
    expect((await settled(calls.handle(callRequest()))).code).toBe('duplicate_call');
    calls.settleSocket(runtime as unknown as WebSocket);
    expect((await settled(first)).code).toBe('runtime_offline');
  });
});

describe('MCP relay admission', () => {
  function admit(sockets: TestSocket[], clientId: string) {
    return relay(sockets).fetch(
      new Request('https://relay.test/v1/relay/runtime-1', {
        headers: {
          upgrade: 'websocket',
          'x-alera-relay-claims': base64Url(JSON.stringify(relayAttachment('mobile', clientId))),
        },
      }),
    );
  }

  test('reserves client ids starting with ~', async () => {
    const response = await admit([mcpRuntime('full')], '~mcp');
    expect(response.status).toBe(403);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe('invalid_relay_client');
  });

  test('refuses phones when the runtime turned Remote Access off', async () => {
    const runtime = new TestSocket({ ...relayAttachment('runtime', 'runtime-1'), mobileAccess: false });
    const response = await admit([runtime], 'mobile-1');
    expect(response.status).toBe(503);
    expect(((await response.json()) as { error: { code: string } }).error.code).toBe('relay_runtime_unavailable');
  });

  test('a runtime cannot route ~ frames to phones', () => {
    const runtime = mcpRuntime('full');
    const mobile = new TestSocket(relayAttachment('mobile', '~mcp'));
    relay([runtime, mobile]).webSocketMessage(
      runtime as unknown as WebSocket,
      mcpFrame({ type: 'mcp.result', id: 'x' }).buffer as ArrayBuffer,
    );
    expect(mobile.sent).toBeEmpty();
  });

  test('relay grants validate MCP and mobile access claims', async () => {
    const env = {
      ...environment(),
      RELAY_ISSUER: 'https://api.alera.build',
      RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
    };
    const valid = await signedRelayGrant(120, { mcpAccess: 'read', mobileAccess: false } as never);
    const claims = await verifyRelayGrant(valid.grant, env, relayJwks(valid.publicJwk));
    expect(claims?.mcpAccess).toBe('read');
    expect(claims?.mobileAccess).toBe(false);
    for (const overrides of [{ mcpAccess: 'admin' }, { mobileAccess: 'no' }]) {
      const invalid = await signedRelayGrant(120, overrides as never);
      expect(await verifyRelayGrant(invalid.grant, env, relayJwks(invalid.publicJwk))).toBeNull();
    }
  });
});
