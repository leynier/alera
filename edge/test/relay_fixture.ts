import { RuntimeRelayDurableObject, type EdgeEnvironment } from '../src/index';
export function environment(success = true): EdgeEnvironment {
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

export function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  return btoa(String.fromCharCode(...bytes))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

export function relayFrame(clientId: string, payload: number[] = [1]): Uint8Array {
  const id = new TextEncoder().encode(clientId);
  return new Uint8Array([(id.length >> 8) & 0xff, id.length & 0xff, ...id, ...payload]);
}

export function relayAttachment(role: 'runtime' | 'mobile', clientId: string, expiresIn = 120) {
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

export async function signedRelayGrant(
  expiresIn = 120,
  overrides: Partial<ReturnType<typeof relayAttachment>> = {},
  kid = 'key-1',
) {
  const keyPair = (await crypto.subtle.generateKey({ name: 'Ed25519', namedCurve: 'Ed25519' }, true, [
    'sign',
    'verify',
  ])) as CryptoKeyPair;
  const publicJwk = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JsonWebKey;
  const header = base64Url(JSON.stringify({ alg: 'EdDSA', typ: 'relay+jwt', kid }));
  const encodedClaims = base64Url(
    JSON.stringify({
      ...relayAttachment('mobile', 'mobile-1', expiresIn),
      ...overrides,
    }),
  );
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

export function relayJwks(publicJwk: JsonWebKey) {
  return async () =>
    new Response(
      JSON.stringify({
        keys: [{ ...publicJwk, kid: 'key-1', alg: 'EdDSA' }],
      }),
    );
}

export function relayEnvironment(stub: DurableObjectStub): EdgeEnvironment {
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

export class TestSocket {
  constructor(
    public attachment: ReturnType<typeof relayAttachment> & {
      suppressDisconnect?: boolean;
      controlProtocol?: boolean;
      connectionId?: string;
      awaitingRuntime?: boolean;
    },
  ) {}

  readonly sent: Uint8Array[] = [];
  closed: { code: number; reason: string } | null = null;

  deserializeAttachment() {
    return this.attachment;
  }

  serializeAttachment(
    attachment: ReturnType<typeof relayAttachment> & {
      suppressDisconnect?: boolean;
      controlProtocol?: boolean;
    },
  ) {
    this.attachment = attachment;
  }

  send(value: Uint8Array) {
    this.sent.push(value);
  }

  close(code: number, reason: string) {
    this.closed = { code, reason };
  }
}

export function relayObject(sockets: TestSocket[]): RuntimeRelayDurableObject {
  return new RuntimeRelayDurableObject({
    getWebSockets: () => sockets as unknown as WebSocket[],
  } as unknown as DurableObjectState);
}
