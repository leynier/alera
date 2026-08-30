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

async function signedRelayGrant(expiresIn = 120) {
  const keyPair = (await crypto.subtle.generateKey({ name: 'Ed25519', namedCurve: 'Ed25519' }, true, [
    'sign',
    'verify',
  ])) as CryptoKeyPair;
  const publicJwk = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JsonWebKey;
  const header = base64Url(JSON.stringify({ alg: 'EdDSA', typ: 'relay+jwt', kid: 'key-1' }));
  const encodedClaims = base64Url(JSON.stringify(relayAttachment('mobile', 'mobile-1', expiresIn)));
  const signingInput = `${header}.${encodedClaims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'Ed25519' }, keyPair.privateKey, new TextEncoder().encode(signingInput)),
  );
  return {
    grant: `${signingInput}.${base64Url(signature)}`,
    publicJwk,
    signingInput,
  };
}

function relayJwks(publicJwk: JsonWebKey) {
  return async () =>
    new Response(
      JSON.stringify({
        keys: [{ ...publicJwk, kid: 'key-1', alg: 'EdDSA' }],
      }),
    );
}

function relayEnvironment(stub: DurableObjectStub): EdgeEnvironment {
  return {
    ...environment(),
    RELAY_ENABLED: 'true',
    RELAY_ISSUER: 'https://api.alera.build',
    RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
    RELAY_OBJECTS: {
      idFromName: () => ({}) as DurableObjectId,
      get: () => stub,
    },
  };
}

class TestSocket {
  constructor(public attachment: ReturnType<typeof relayAttachment> & { suppressDisconnect?: boolean }) {}

  readonly sent: Uint8Array[] = [];
  closed: { code: number; reason: string } | null = null;

  deserializeAttachment() {
    return this.attachment;
  }

  serializeAttachment(attachment: ReturnType<typeof relayAttachment> & { suppressDisconnect?: boolean }) {
    this.attachment = attachment;
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
  test('rejects mobile admission immediately while its runtime is unavailable', async () => {
    for (const runtimes of [[], [new TestSocket(relayAttachment('runtime', 'runtime-1', -1))]]) {
      const response = await relayObject(runtimes).fetch(new Request('https://relay.test/v1/relay/runtime-1', {
        headers: { upgrade: 'websocket', 'x-alera-relay-claims': base64Url(JSON.stringify(relayAttachment('mobile', 'mobile-1'))) },
      }));
      expect(response.status).toBe(503);
    }
  });

  test('an error followed by close disconnects a mobile only once', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));
    const relay = relayObject([runtime, mobile]);
    relay.webSocketError(mobile as unknown as WebSocket);
    relay.webSocketClose(mobile as unknown as WebSocket);
    expect(runtime.sent).toEqual([relayFrame('mobile-1', [])]);
  });

  test('late frames cannot cross between a replaced socket and a new session', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const oldMobile = new TestSocket({ ...relayAttachment('mobile', 'mobile-1'), suppressDisconnect: true });
    const newMobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));
    const relay = relayObject([runtime, oldMobile, newMobile]);
    const frame = relayFrame('mobile-1');
    relay.webSocketMessage(oldMobile as unknown as WebSocket, frame.buffer as ArrayBuffer);
    expect(runtime.sent).toBeEmpty();
    relay.webSocketMessage(runtime as unknown as WebSocket, frame.buffer as ArrayBuffer);
    expect(oldMobile.sent).toBeEmpty();
    expect(newMobile.sent).toEqual([frame]);
  });

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

  test('does not notify the runtime again when a replaced mobile closes', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const mobile = new TestSocket({
      ...relayAttachment('mobile', 'mobile-1'),
      suppressDisconnect: true,
    });

    relayObject([runtime, mobile]).webSocketClose(mobile as unknown as WebSocket);

    expect(runtime.sent).toBeEmpty();
  });

  test('disconnects matching mobiles when the runtime disconnects', () => {
    const runtime = new TestSocket(relayAttachment('runtime', 'runtime-1'));
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));
    const otherRuntimeMobile = new TestSocket({
      ...relayAttachment('mobile', 'mobile-2'),
      runtimeId: 'runtime-2',
    });

    relayObject([runtime, mobile, otherRuntimeMobile]).webSocketClose(runtime as unknown as WebSocket);

    expect(mobile.attachment.suppressDisconnect).toBeTrue();
    expect(mobile.closed).toEqual({
      code: 4002,
      reason: 'runtime disconnected',
    });
    expect(otherRuntimeMobile.closed).toBeNull();
  });

  test('does not disconnect a new mobile when a replaced runtime closes later', () => {
    const oldRuntime = new TestSocket({
      ...relayAttachment('runtime', 'runtime-1'),
      suppressDisconnect: true,
    });
    const mobile = new TestSocket(relayAttachment('mobile', 'mobile-1'));

    relayObject([oldRuntime, mobile]).webSocketClose(oldRuntime as unknown as WebSocket);

    expect(mobile.closed).toBeNull();
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

  for (const relayEnabled of [undefined, 'false']) {
    test(`proxies the relay route to the backend when RELAY_ENABLED is ${relayEnabled ?? 'absent'}`, async () => {
      const response = await handleRequest(
        new Request('https://api.alera.build/v1/relay/deploy-probe'),
        {
          ...environment(),
          RELAY_ENABLED: relayEnabled,
        },
        async (originRequest) => {
          expect(originRequest.url).toBe('https://alera-cloud.example.run.app/v1/relay/deploy-probe');
          return new Response('backend route not found', { status: 404 });
        },
      );

      expect(response.status).toBe(404);
      expect(await response.text()).toBe('backend route not found');
    });
  }

  test('requires WebSocket only when RELAY_ENABLED is exactly true', async () => {
    const response = await handleRequest(new Request('https://api.alera.build/v1/relay/deploy-probe'), {
      ...environment(),
      RELAY_ENABLED: 'true',
    });

    expect(response.status).toBe(426);
  });

  for (const controlPath of ['/v1/relay/identity', '/v1/relay/grants']) {
    test(`proxies ${controlPath} to the control plane when the relay is enabled`, async () => {
      let originCalled = false;
      const response = await handleRequest(
        new Request(`https://api.alera.build${controlPath}`, {
          body: '{}',
          headers: { authorization: 'Bearer account-token' },
          method: 'POST',
        }),
        {
          ...environment(),
          RELAY_ENABLED: 'true',
        },
        async (originRequest) => {
          originCalled = true;
          expect(originRequest.url).toBe(`https://alera-cloud.example.run.app${controlPath}`);
          expect(originRequest.headers.get('x-alera-origin-auth')).toBe('edge-secret');
          return new Response(null, { status: 204 });
        },
      );

      expect(response.status).toBe(204);
      expect(originCalled).toBeTrue();
    });
  }

  for (const [missingValue, relayConfiguration] of [
    [
      'Durable Object binding',
      {
        RELAY_ISSUER: 'https://api.alera.build',
        RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
      },
    ],
    [
      'issuer',
      {
        RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
        RELAY_OBJECTS: {} as EdgeEnvironment['RELAY_OBJECTS'],
      },
    ],
    [
      'JWKS URL',
      {
        RELAY_ISSUER: 'https://api.alera.build',
        RELAY_OBJECTS: {} as EdgeEnvironment['RELAY_OBJECTS'],
      },
    ],
  ] as const) {
    test(`rejects enabled relay connections when the ${missingValue} is missing`, async () => {
      const response = await handleRequest(
        new Request('https://api.alera.build/v1/relay/runtime-1', {
          headers: { upgrade: 'websocket' },
        }),
        {
          ...environment(),
          RELAY_ENABLED: 'true',
          ...relayConfiguration,
        },
      );

      expect(response.status).toBe(503);
    });
  }

  test('requires a bearer grant for relay connections', async () => {
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/relay/runtime-1', {
        headers: { upgrade: 'websocket' },
      }),
      {
        ...environment(),
        RELAY_ENABLED: 'true',
        RELAY_ISSUER: 'https://api.alera.build',
        RELAY_JWKS_URL: 'https://api.alera.build/.well-known/jwks.json',
        RELAY_OBJECTS: {} as EdgeEnvironment['RELAY_OBJECTS'],
      },
    );
    expect(response.status).toBe(401);
  });

  test('verifies a grant and forwards only claims to the runtime object', async () => {
    const { grant, publicJwk } = await signedRelayGrant();
    const forwarded: Request[] = [];
    const originRequests: Request[] = [];
    const stub = {
      fetch(request: Request) {
        forwarded.push(request);
        return Promise.resolve(new Response('connected'));
      },
    } as unknown as DurableObjectStub;
    const environmentWithRelay = relayEnvironment(stub);
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/relay/runtime-1', {
        headers: {
          authorization: `Bearer ${grant}`,
          upgrade: 'websocket',
        },
      }),
      environmentWithRelay,
      async (originRequest) => {
        originRequests.push(originRequest);
        return relayJwks(publicJwk)();
      },
    );

    expect(response.status).toBe(200);
    expect(originRequests).toHaveLength(1);
    expect(originRequests[0].url).toBe('https://alera-cloud.example.run.app/.well-known/jwks.json');
    expect(originRequests[0].headers.get('x-alera-origin-auth')).toBe('edge-secret');
    expect(originRequests[0].headers.get('x-forwarded-host')).toBe('api.alera.build');
    expect(forwarded).toHaveLength(1);
    expect(forwarded[0].headers.get('authorization')).toBeNull();
    expect(forwarded[0].headers.get('x-alera-relay-claims')).toBeTruthy();
  });

  test('rejects a relay grant with an invalid signature during the handshake', async () => {
    const { publicJwk, signingInput } = await signedRelayGrant();
    let forwarded = false;
    const stub = {
      fetch() {
        forwarded = true;
        return Promise.resolve(new Response('unexpected'));
      },
    } as unknown as DurableObjectStub;
    const invalidGrant = `${signingInput}.${base64Url(new Uint8Array(64))}`;
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/relay/runtime-1', {
        headers: {
          authorization: `Bearer ${invalidGrant}`,
          upgrade: 'websocket',
        },
      }),
      relayEnvironment(stub),
      undefined,
      relayJwks(publicJwk),
    );

    expect(response.status).toBe(403);
    expect(forwarded).toBeFalse();
  });

  test('rejects an expired relay grant during the handshake', async () => {
    const { grant, publicJwk } = await signedRelayGrant(-1);
    let forwarded = false;
    const stub = {
      fetch() {
        forwarded = true;
        return Promise.resolve(new Response('unexpected'));
      },
    } as unknown as DurableObjectStub;
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/relay/runtime-1', {
        headers: {
          authorization: `Bearer ${grant}`,
          upgrade: 'websocket',
        },
      }),
      relayEnvironment(stub),
      undefined,
      relayJwks(publicJwk),
    );

    expect(response.status).toBe(403);
    expect(forwarded).toBeFalse();
  });
});
