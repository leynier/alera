import type { EdgeEnvironment } from './index';
export type RelayFetch = (request: Request) => Promise<Response>;
const RELAY_AUDIENCE = 'alera-relay';
export interface RelayClaims {
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

export interface RelayAttachment extends RelayClaims {
  suppressDisconnect?: boolean;
  controlProtocol?: boolean;
  connectionId?: string;
  awaitingRuntime?: boolean;
}

export const RELAY_CONTROL_PROTOCOL = 'alera-relay-control-v1';
export class RelayAuthorizationUnavailable extends Error {}
type SigningKey = JsonWebKey & { kid?: string };
const caches = new WeakMap<
  object,
  Map<
    string,
    {
      until: number;
      fetched: number;
      failureUntil?: number;
      unknownRefresh?: number;
      keys: SigningKey[];
      pending?: Promise<SigningKey[]>;
    }
  >
>();

async function signingKeys(env: EdgeEnvironment, fetcher: RelayFetch, kid: string): Promise<SigningKey[]> {
  let cache = caches.get(env);
  if (!cache) {
    cache = new Map();
    caches.set(env, cache);
  }
  const url = env.RELAY_JWKS_URL!;
  let entry = cache.get(url);
  const now = Date.now();
  if (entry?.pending) return entry.pending;
  if (entry?.failureUntil && entry.failureUntil > now) throw new Error('Signing keys unavailable');
  if (
    entry &&
    entry.until > now &&
    (entry.keys.some((key) => key.kid === kid) || now - (entry.unknownRefresh ?? 0) < 5000)
  )
    return entry.keys;
  entry ??= { until: 0, fetched: 0, keys: [] };
  cache.set(url, entry);
  const target = entry;
  if (entry.until > now && !entry.keys.some((key) => key.kid === kid)) entry.unknownRefresh = now;
  const pending = (async () => {
    const response = await fetcher(
      new Request(url, {
        headers: { accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      }),
    );
    if (!response.ok) throw new Error('Signing keys unavailable');
    const reader = response.body?.getReader();
    if (!reader) throw new Error('Missing signing key response');
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 65536) throw new Error('Signing key response too large');
        chunks.push(value);
      }
    } finally {
      await reader.cancel();
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const jwks = JSON.parse(new TextDecoder().decode(bytes)) as {
      keys?: SigningKey[];
    };
    if (!Array.isArray(jwks.keys) || jwks.keys.length > 32) throw new Error('Invalid signing keys');
    target.keys = jwks.keys;
    target.fetched = Date.now();
    target.until = target.fetched + 60000;
    return target.keys;
  })();
  target.pending = pending;
  try {
    return await pending;
  } catch (error) {
    target.failureUntil = Date.now() + 1000;
    throw error;
  } finally {
    if (target.pending === pending) target.pending = undefined;
  }
}

export function sameRelayIdentity(a: RelayClaims, b: RelayClaims): boolean {
  return (
    a.iss === b.iss &&
    a.aud === b.aud &&
    a.accountId === b.accountId &&
    a.runtimeId === b.runtimeId &&
    a.clientId === b.clientId &&
    a.role === b.role &&
    a.keyVersion === b.keyVersion &&
    a.clientPublicKey === b.clientPublicKey &&
    a.runtimePublicKey === b.runtimePublicKey
  );
}

export function controlFrame(value: unknown): Uint8Array {
  const json = new TextEncoder().encode(JSON.stringify(value));
  const bytes = new Uint8Array(json.length + 2);
  bytes.set(json, 2);
  return bytes;
}

export function base64UrlBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function decodeJsonPart<T>(value: string): T {
  return JSON.parse(new TextDecoder().decode(base64UrlBytes(value))) as T;
}

export function bearerToken(request: Request): string | null {
  const value = request.headers.get('authorization');
  return value?.startsWith('Bearer ') ? value.slice('Bearer '.length) : null;
}

export async function verifyRelayGrant(
  token: string,
  env: EdgeEnvironment,
  fetcher: RelayFetch = (request) => fetch(request),
): Promise<RelayAttachment | null> {
  const parts = token.split('.');
  if (token.length > 16384 || parts.length !== 3 || !env.RELAY_JWKS_URL) return null;
  let header: { alg?: string; typ?: string; kid?: string };
  let claims: RelayClaims;
  try {
    header = decodeJsonPart(parts[0]);
    claims = decodeJsonPart(parts[1]);
  } catch {
    return null;
  }
  if (!header || typeof header !== 'object' || !claims || typeof claims !== 'object') return null;
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
    !Number.isSafeInteger(claims.exp) ||
    !Number.isSafeInteger(claims.iat) ||
    !Number.isSafeInteger(claims.nbf) ||
    claims.exp <= claims.iat ||
    claims.exp - claims.iat > 120 ||
    claims.nbf > claims.exp ||
    ![claims.jti, claims.accountId, claims.runtimeId, claims.clientId].every(
      (value) => typeof value === 'string' && value.length > 0 && value.length <= 128,
    ) ||
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

  let keys: SigningKey[];
  try {
    keys = await signingKeys(env, fetcher, header.kid);
  } catch {
    throw new RelayAuthorizationUnavailable('Relay signing keys unavailable');
  }
  const key = keys.find(
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
    return valid && claims.exp > Math.floor(Date.now() / 1000) ? claims : null;
  } catch {
    return null;
  }
}
