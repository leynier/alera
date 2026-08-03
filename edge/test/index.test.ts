import { describe, expect, test } from 'bun:test';
import { handleRequest, relayFrameClientId, RuntimeRelayDurableObject, type EdgeEnvironment } from '../src/index';

function environment(success = true): EdgeEnvironment {
  return {
    EDGE_BURST_LIMITER: {
      async limit() {
        return { success };
      },
    },
    EDGE_ORIGIN_TOKEN: 'edge-secret',
    ORIGIN_BASE_URL: 'https://alera-cloud.example.run.app',
  };
}

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  return btoa(String.fromCharCode(...bytes))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function relayFrame(clientId: string, payload: number[] = [1]): Uint8Array {
  const id = new TextEncoder().encode(clientId);
  return new Uint8Array([(id.length >> 8) & 0xff, id.length & 0xff, ...id, ...payload]);
}

function relayAttachment(role: 'runtime' | 'mobile', clientId: string, expiresIn = 120) {
  const now = Math.floor(Date.now() / 1000);
  return {
    iss: 'https://api.alera.build',
    aud: 'alera-relay',
    exp: now + expiresIn,
    iat: now,
    nbf: now,
    jti: `${role}-${clientId}`,
    accountId: 'account-1',
    runtimeId: 'runtime-1',
    clientId,
    role,
    keyVersion: 1,
    clientPublicKey: base64Url(new Uint8Array(32).fill(1)),
    runtimePublicKey: base64Url(new Uint8Array(32).fill(2)),
  };
}

class TestSocket {
  constructor(readonly attachment: ReturnType<typeof relayAttachment>) {}

  readonly sent: Uint8Array[] = [];
  closed: { code: number; reason: string } | null = null;

  deserializeAttachment() {
    return this.attachment;
  }

  send(value: Uint8Array) {
    this.sent.push(value);
  }

  close(code: number, reason: string) {
    this.closed = { code, reason };
  }
}

function relayObject(sockets: TestSocket[]): RuntimeRelayDurableObject {
  return new RuntimeRelayDurableObject({
    getWebSockets: () => sockets as unknown as WebSocket[],
  } as unknown as DurableObjectState);
}

describe('Alera API edge', () => {
  test('routes runtime frames only to the addressed mobile', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const mobileOne = new TestSocket(relayAttachment('mobile', 'mobile-1'));
    const mobileTwo = new TestSocket(relayAttachment('mobile', 'mobile-2'));
    const frame = relayFrame('mobile-1');

    relayObject([runtime, mobileOne, mobileTwo]).webSocketMessage(
      runtime as unknown as WebSocket,
      frame.buffer as ArrayBuffer,
    );

    expect(relayFrameClientId(frame)).toBe('mobile-1');
    expect(mobileOne.sent).toEqual([frame]);
    expect(mobileTwo.sent).toBeEmpty();
  });

  test('rejects a mobile frame that claims another client id', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));

    relayObject([runtime, mobile]).webSocketMessage(
      mobile as unknown as WebSocket,
      relayFrame('mobile-2').buffer as ArrayBuffer,
    );

    expect(mobile.closed).toEqual({
      code: 1008,
      reason: 'relay client id mismatch',
    });
    expect(runtime.sent).toBeEmpty();
  });

  test('stops forwarding when a relay grant expires', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1', -1));
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));

    relayObject([runtime, mobile]).webSocketMessage(
      runtime as unknown as WebSocket,
      relayFrame('mobile-1').buffer as ArrayBuffer,
    );

    expect(runtime.closed).toEqual({
      code: 4003,
      reason: 'relay grant expired',
    });
    expect(mobile.sent).toBeEmpty();
  });

  test('notifies the runtime when a mobile disconnects', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));

    relayObject([runtime, mobile]).webSocketClose(mobile as unknown as WebSocket);

    expect(runtime.sent).toEqual([relayFrame('mobile-1', [])]);
  });

  test('rejects paths outside the public API', async () => {
    const response = await handleRequest(new Request('https://api.alera.build/admin'), environment());
    expect(response.status).toBe(404);
  });

  test('rejects unsupported methods', async () => {
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/account', { method: 'PATCH' }),
      environment(),
    );
    expect(response.status).toBe(405);
  });

  test('overwrites the origin credential and routes to Cloud Run', async () => {
    const request = new Request('https://api.alera.build/v1/account?view=full', {
      headers: {
        authorization: 'Bearer account-token',
        cookie: 'must-not-cross-the-edge=1',
        'x-alera-origin-auth': 'attacker-value',
      },
      method: 'POST',
    });

    const response = await handleRequest(request, environment(), async (originRequest) => {
      const proxied = originRequest as Request;
      expect(proxied.url).toBe('https://alera-cloud.example.run.app/v1/account?view=full');
      expect(proxied.headers.get('x-alera-origin-auth')).toBe('edge-secret');
      expect(proxied.headers.get('authorization')).toBe('Bearer account-token');
      expect(proxied.headers.get('cookie')).toBeNull();
      return new Response('ok');
    });

    expect(response.status).toBe(200);
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');
  });

  test('rate limits mutating requests before reaching the origin', async () => {
    let originCalled = false;
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/auth/exchange', {
        method: 'POST',
      }),
      environment(false),
      async () => {
        originCalled = true;
        return new Response('unexpected');
      },
    );

    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('60');
    expect(originCalled).toBeFalse();
  });

  test('maps an unreachable origin to a bounded error', async () => {
    const response = await handleRequest(new Request('https://api.alera.build/health'), environment(), async () => {
      throw new Error('network unavailable');
    });
    expect(response.status).toBe(502);
  });

  test('requires a bearer grant for relay connections', async () => {
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/relay/runtime-1', {
        headers: { upgrade: 'websocket' },
      }),
      {
        ...environment(),
        RELAY_ISSUER: 'https://api.alera.build',
        RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
        RELAY_OBJECTS: {} as EdgeEnvironment['RELAY_OBJECTS'],
      },
    );
    expect(response.status).toBe(401);
  });

  test('verifies a grant and forwards only claims to the runtime object', async () => {
    const keyPair = (await crypto.subtle.generateKey({ name: 'Ed25519', namedCurve: 'Ed25519' }, true, [
      'sign',
      'verify',
    ])) as CryptoKeyPair;
    const publicJwk = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JsonWebKey;
    const now = Math.floor(Date.now() / 1000);
    const claims = {
      iss: 'https://api.alera.build',
      aud: 'alera-relay',
      exp: now + 120,
      iat: now,
      nbf: now,
      jti: 'grant-1',
      accountId: 'account-1',
      runtimeId: 'runtime-1',
      clientId: 'mobile-1',
      role: 'mobile',
      keyVersion: 1,
      clientPublicKey: base64Url(new Uint8Array(32).fill(1)),
      runtimePublicKey: base64Url(new Uint8Array(32).fill(2)),
    };
    const header = base64Url(JSON.stringify({ alg: 'EdDSA', typ: 'relay+jwt', kid: 'key-1' }));
    const encodedClaims = base64Url(JSON.stringify(claims));
    const signingInput = `${header}.${encodedClaims}`;
    const signature = new Uint8Array(
      await crypto.subtle.sign({ name: 'Ed25519' }, keyPair.privateKey, new TextEncoder().encode(signingInput)),
    );
    const grant = `${signingInput}.${base64Url(signature)}`;
    const forwarded: Request[] = [];
    const stub = {
      fetch(request: Request) {
        forwarded.push(request);
        return Promise.resolve(new Response('connected'));
      },
    } as unknown as DurableObjectStub;
    const environmentWithRelay = {
      ...environment(),
      RELAY_ISSUER: 'https://api.alera.build',
      RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
      RELAY_OBJECTS: {
        idFromName: () => ({}) as DurableObjectId,
        get: () => stub,
      },
    } as EdgeEnvironment;
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/relay/runtime-1', {
        headers: {
          authorization: `Bearer ${grant}`,
          upgrade: 'websocket',
        },
      }),
      environmentWithRelay,
      undefined,
      async () =>
        new Response(
          JSON.stringify({
            keys: [{ ...publicJwk, kid: 'key-1', alg: 'EdDSA' }],
          }),
        ),
    );

    expect(response.status).toBe(200);
    expect(forwarded).toHaveLength(1);
    expect(forwarded[0].headers.get('authorization')).toBeNull();
    expect(forwarded[0].headers.get('x-alera-relay-claims')).toBeTruthy();
  });
});
