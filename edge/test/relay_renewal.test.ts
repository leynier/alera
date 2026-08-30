import { describe, expect, test } from 'bun:test';
import { RuntimeRelayDurableObject } from '../src/index';
import { controlFrame, verifyRelayGrant } from '../src/relay_authorization';
import { environment, relayAttachment, signedRelayGrant, relayJwks, TestSocket } from './relay_fixture';

function configured() {
  return {
    ...environment(),
    RELAY_ISSUER: 'https://api.alera.build',
    RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
  };
}

describe('relay authorization renewal', () => {
  test('renews the same socket without disconnecting its runtime or forwarding the grant', async () => {
    const signed = await signedRelayGrant();
    const mobile = new TestSocket({
      ...relayAttachment('mobile', 'mobile-1', 30),
      jti: 'old',
      controlProtocol: true,
    });
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const relay = new RuntimeRelayDurableObject(
      {
        getWebSockets: () => [mobile, runtime],
      } as unknown as DurableObjectState,
      configured(),
      relayJwks(signed.publicJwk),
    );
    const request = controlFrame({
      type: 'auth.renew',
      id: 1,
      grant: signed.grant,
    });
    await relay.webSocketMessage(mobile as unknown as WebSocket, request.buffer as ArrayBuffer);
    expect(mobile.closed).toBeNull();
    expect(runtime.sent).toBeEmpty();
    expect(mobile.attachment.exp).toBeGreaterThan(Math.floor(Date.now() / 1000) + 100);
    expect(JSON.parse(new TextDecoder().decode(mobile.sent[0].subarray(2))).type).toBe('auth.renewed');
  });

  test('does not revive a socket replaced while signing keys are loading', async () => {
    const signed = await signedRelayGrant();
    let release!: () => void;
    const blocked = new Promise<void>((resolve) => {
      release = resolve;
    });
    const mobile = new TestSocket({
      ...relayAttachment('mobile', 'mobile-1', 30),
      jti: 'old',
      controlProtocol: true,
    });
    const relay = new RuntimeRelayDurableObject(
      { getWebSockets: () => [mobile] } as unknown as DurableObjectState,
      configured(),
      async () => {
        await blocked;
        return relayJwks(signed.publicJwk)();
      },
    );
    const pending = relay.webSocketMessage(
      mobile as unknown as WebSocket,
      controlFrame({ type: 'auth.renew', id: 1, grant: signed.grant }).buffer as ArrayBuffer,
    );
    mobile.attachment.suppressDisconnect = true;
    release();
    await pending;
    expect(mobile.sent).toBeEmpty();
    expect(mobile.attachment.jti).toBe('old');
  });

  test('rejects a different client and an expired connection', async () => {
    const signed = await signedRelayGrant();
    for (const expiresIn of [30, -1]) {
      const mobile = new TestSocket({
        ...relayAttachment('mobile', 'mobile-2', expiresIn),
        controlProtocol: true,
      });
      const relay = new RuntimeRelayDurableObject(
        { getWebSockets: () => [mobile] } as unknown as DurableObjectState,
        configured(),
        relayJwks(signed.publicJwk),
      );
      await relay.webSocketMessage(
        mobile as unknown as WebSocket,
        controlFrame({ type: 'auth.renew', id: 1, grant: signed.grant }).buffer as ArrayBuffer,
      );
      expect(mobile.attachment.clientId).toBe('mobile-2');
      if (expiresIn < 0) expect(mobile.closed?.code).toBe(4003);
      else expect(JSON.parse(new TextDecoder().decode(mobile.sent[0].subarray(2))).type).toBe('auth.error');
    }
  });

  test('shares concurrent signing key lookups', async () => {
    const signed = await signedRelayGrant();
    const env = configured();
    let requests = 0;
    const fetcher = async () => {
      requests++;
      return relayJwks(signed.publicJwk)();
    };
    const verified = await Promise.all(
      Array.from({ length: 8 }, () => verifyRelayGrant(signed.grant, env, fetcher)),
    );
    expect(verified.every(Boolean)).toBe(true);
    expect(requests).toBe(1);
  });
});

describe('relay renewal recovery boundaries', () => {
  test('runtime cleanup cannot close a replacement mobile', async () => {
    const runtime = new TestSocket({
      ...relayAttachment('runtime', 'runtime-1'),
      controlProtocol: true,
    });
    const mobile = new TestSocket({
      ...relayAttachment('mobile', 'mobile-1'),
      connectionId: 'new-connection',
    });
    const relay = new RuntimeRelayDurableObject(
      {
        getWebSockets: () => [runtime, mobile],
      } as unknown as DurableObjectState,
      configured(),
    );
    const close = (connectionId: string) =>
      relay.webSocketMessage(
        runtime as unknown as WebSocket,
        controlFrame({
          type: 'peer.close',
          clientId: 'mobile-1',
          connectionId,
          code: 1013,
        }).buffer as ArrayBuffer,
      );
    await close('old-connection');
    expect(mobile.closed).toBeNull();
    await close('new-connection');
    expect(mobile.closed?.code).toBe(1013);
    expect(runtime.closed).toBeNull();
  });

  test('a failed JWKS fetch preserves current authorization and is coalesced', async () => {
    const signed = await signedRelayGrant();
    const mobile = new TestSocket({
      ...relayAttachment('mobile', 'mobile-1', 30),
      jti: 'old',
      controlProtocol: true,
    });
    let calls = 0;
    const relay = new RuntimeRelayDurableObject(
      { getWebSockets: () => [mobile] } as unknown as DurableObjectState,
      configured(),
      async () => {
        calls++;
        return new Response(null, { status: 503 });
      },
    );
    for (let id = 1; id <= 2; id++)
      await relay.webSocketMessage(
        mobile as unknown as WebSocket,
        controlFrame({ type: 'auth.renew', id, grant: signed.grant }).buffer as ArrayBuffer,
      );
    expect(calls).toBe(1);
    expect(mobile.attachment.jti).toBe('old');
    expect(mobile.closed).toBeNull();
    expect(JSON.parse(new TextDecoder().decode(mobile.sent[0].subarray(2))).code).toBe(
      'relay_authorization_unavailable',
    );
  });

  test('a reconstructed object retains renewal and connection identity', async () => {
    const signed = await signedRelayGrant();
    const mobile = new TestSocket({
      ...relayAttachment('mobile', 'mobile-1', 30),
      jti: 'old',
      controlProtocol: true,
    });
    const context = {
      getWebSockets: () => [mobile],
    } as unknown as DurableObjectState;
    const env = configured();
    const frame = controlFrame({
      type: 'auth.renew',
      id: 1,
      grant: signed.grant,
    }).buffer as ArrayBuffer;
    await new RuntimeRelayDurableObject(context, env, relayJwks(signed.publicJwk)).webSocketMessage(
      mobile as unknown as WebSocket,
      frame,
    );
    await new RuntimeRelayDurableObject(context, env, relayJwks(signed.publicJwk)).webSocketMessage(
      mobile as unknown as WebSocket,
      frame,
    );
    expect(mobile.sent).toHaveLength(2);
    expect(mobile.attachment.connectionId).toBe('old');
    expect(mobile.closed).toBeNull();
  });

  test('older and disabled clients cannot opt into renewal', async () => {
    for (const enabled of [true, false]) {
      const mobile = new TestSocket({
        ...relayAttachment('mobile', 'mobile-1'),
        controlProtocol: !enabled,
      });
      const relay = new RuntimeRelayDurableObject(
        { getWebSockets: () => [mobile] } as unknown as DurableObjectState,
        { ...configured(), RELAY_RENEWAL_ENABLED: String(enabled) },
      );
      await relay.webSocketMessage(
        mobile as unknown as WebSocket,
        controlFrame({ type: 'auth.renew', id: 1, grant: 'unused' }).buffer as ArrayBuffer,
      );
      expect(mobile.closed?.code).toBe(enabled ? 1008 : 1012);
    }
  });

  test('rejects oversized lifetimes before consulting signing keys', async () => {
    const signed = await signedRelayGrant(121);
    let requests = 0;
    expect(
      await verifyRelayGrant(signed.grant, configured(), async () => {
        requests++;
        return relayJwks(signed.publicJwk)();
      }),
    ).toBeNull();
    expect(requests).toBe(0);
  });
});

test('pending connections do not receive ciphertext from a replaced session', async () => {
  const runtime = new TestSocket({
    ...relayAttachment('runtime', 'runtime-1'),
    controlProtocol: true,
  });
  const mobile = new TestSocket({
    ...relayAttachment('mobile', 'mobile-1'),
    awaitingRuntime: true,
    connectionId: 'new',
  });
  const relay = new RuntimeRelayDurableObject(
    { getWebSockets: () => [runtime, mobile] } as unknown as DurableObjectState,
    configured(),
  );
  const data = new Uint8Array([0, 8, ...new TextEncoder().encode('mobile-1'), 10, 20]);
  relay.webSocketMessage(runtime as unknown as WebSocket, data.buffer);
  expect(mobile.sent).toBeEmpty();
  await relay.webSocketMessage(
    runtime as unknown as WebSocket,
    controlFrame({
      type: 'peer.ready',
      clientId: 'mobile-1',
      connectionId: 'old',
    }).buffer as ArrayBuffer,
  );
  expect(mobile.attachment.awaitingRuntime).toBe(true);
  await relay.webSocketMessage(
    runtime as unknown as WebSocket,
    controlFrame({
      type: 'peer.ready',
      clientId: 'mobile-1',
      connectionId: 'new',
    }).buffer as ArrayBuffer,
  );
  relay.webSocketMessage(runtime as unknown as WebSocket, data.buffer);
  expect(mobile.sent).toHaveLength(1);
});
