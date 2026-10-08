import type { EdgeEnvironment } from '../index';
import { decodeJwt, verifyJwtSignature, type RelayFetch } from '../relay_authorization';

interface AccessClaims {
  iss?: unknown;
  aud?: unknown;
  exp?: unknown;
  iat?: unknown;
  nbf?: unknown;
  sub?: unknown;
  client_id?: unknown;
  client_kind?: unknown;
  scope?: unknown;
}

export interface McpAccess {
  subject: string;
  clientId: string;
  scopes: Set<string>;
}

const CLOCK_SKEW_SECONDS = 30;

export function mcpBearerToken(request: Request): string | null {
  const match = /^Bearer[ ]+([^\s]+)\s*$/i.exec(request.headers.get('authorization') ?? '');
  return match ? match[1] : null;
}

/**
 * Verifies an MCP access token locally. Returns null for an invalid token and throws
 * RelayAuthorizationUnavailable when the signing keys cannot be loaded.
 */
export async function verifyMcpAccessToken(
  token: string,
  env: EdgeEnvironment,
  fetcher: RelayFetch,
): Promise<McpAccess | null> {
  const decoded = decodeJwt<AccessClaims>(token);
  if (!decoded || !env.MCP_RESOURCE || !env.RELAY_ISSUER) return null;
  const { header, claims } = decoded;
  const now = Math.floor(Date.now() / 1000);
  const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (
    header.alg !== 'EdDSA' ||
    header.typ !== 'at+jwt' ||
    !header.kid ||
    claims.iss !== env.RELAY_ISSUER ||
    !audience.includes(env.MCP_RESOURCE) ||
    claims.client_kind !== 'mcp' ||
    typeof claims.client_id !== 'string' ||
    typeof claims.sub !== 'string' ||
    typeof claims.scope !== 'string' ||
    !Number.isSafeInteger(claims.exp) ||
    !Number.isSafeInteger(claims.iat) ||
    (claims.exp as number) <= now ||
    (claims.iat as number) > now + CLOCK_SKEW_SECONDS ||
    (claims.nbf !== undefined &&
      (!Number.isSafeInteger(claims.nbf) || (claims.nbf as number) > now + CLOCK_SKEW_SECONDS))
  ) {
    return null;
  }
  const scopes = new Set(claims.scope.split(' ').filter(Boolean));
  if (!(await verifyJwtSignature(decoded, env, fetcher))) return null;
  if ((claims.exp as number) <= Math.floor(Date.now() / 1000)) return null;
  return { subject: claims.sub, clientId: claims.client_id, scopes };
}
