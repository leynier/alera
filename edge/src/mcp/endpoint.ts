import { jsonError, type EdgeEnvironment, type OriginFetch } from '../index';
import { RelayAuthorizationUnavailable, type RelayFetch } from '../relay_authorization';
import { mcpBearerToken, verifyMcpAccessToken, type McpAccess } from './access_token';
import {
  corsPreflight,
  emptyMcpResponse,
  isJsonObject,
  jsonRpcError,
  jsonRpcResult,
  JSON_RPC_INVALID_PARAMS,
  JSON_RPC_INVALID_REQUEST,
  JSON_RPC_METHOD_NOT_FOUND,
  JSON_RPC_PARSE_ERROR,
  JSON_RPC_SERVER_ERROR,
  MAX_MCP_BODY_BYTES,
  MCP_INSTRUCTIONS,
  MCP_PATH,
  MCP_PROTOCOL_VERSIONS,
  MCP_SCOPES,
  MCP_SERVER_VERSION,
  mcpHeaders,
  negotiateProtocolVersion,
  type JsonRpcId,
} from './protocol';
import { callTool, type GatewayContext } from './tool_call';
import { listedTools } from './tools';

export interface McpRequestContext {
  env: EdgeEnvironment;
  fetchOrigin: OriginFetch;
  fetchJwks: RelayFetch;
  waitUntil(promise: Promise<unknown>): void;
}

const ALLOWED_METHODS = 'POST, OPTIONS';

async function tokenHash(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function challenge(publicUrl: URL, error?: 'invalid_token' | 'insufficient_scope'): string {
  const metadata = `${publicUrl.origin}/.well-known/oauth-protected-resource${MCP_PATH}`;
  const parts = [`resource_metadata="${metadata}"`, `scope="${MCP_SCOPES}"`];
  if (error) parts.push(`error="${error}"`);
  return `Bearer ${parts.join(', ')}`;
}

function unauthorized(publicUrl: URL, tokenPresent: boolean): Response {
  return new Response(
    JSON.stringify({
      error: tokenPresent ? 'invalid_token' : 'invalid_request',
      error_description: 'A valid Alera MCP access token is required.',
    }),
    {
      status: 401,
      headers: mcpHeaders({
        'content-type': 'application/json; charset=utf-8',
        'www-authenticate': challenge(publicUrl, tokenPresent ? 'invalid_token' : undefined),
      }),
    },
  );
}

function insufficientScope(publicUrl: URL): Response {
  return new Response(
    JSON.stringify({ error: 'insufficient_scope', error_description: 'The token lacks the mcp:read scope.' }),
    {
      status: 403,
      headers: mcpHeaders({
        'content-type': 'application/json; charset=utf-8',
        'www-authenticate': challenge(publicUrl, 'insufficient_scope'),
      }),
    },
  );
}

async function readBody(request: Request): Promise<string | null> {
  const declared = Number(request.headers.get('content-length') ?? '0');
  if (declared > MAX_MCP_BODY_BYTES) return null;
  const reader = request.body?.getReader();
  if (!reader) return '';
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_MCP_BODY_BYTES) return null;
      chunks.push(value);
    }
  } finally {
    await reader.cancel().catch(() => undefined);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

function validId(value: unknown): value is JsonRpcId {
  return typeof value === 'string' || (typeof value === 'number' && Number.isFinite(value));
}

async function dispatch(
  message: Record<string, unknown>,
  id: JsonRpcId,
  access: McpAccess,
  gateway: GatewayContext,
): Promise<Response> {
  const params = message.params === undefined ? {} : message.params;
  if (!isJsonObject(params)) return jsonRpcError(id, JSON_RPC_INVALID_PARAMS, 'Params must be an object.');
  switch (message.method) {
    case 'initialize':
      return jsonRpcResult(id, {
        protocolVersion: negotiateProtocolVersion(params.protocolVersion),
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'alera', title: 'Alera', version: MCP_SERVER_VERSION },
        instructions: MCP_INSTRUCTIONS,
      });
    case 'ping':
      return jsonRpcResult(id, {});
    case 'tools/list':
      return jsonRpcResult(id, { tools: listedTools() });
    case 'tools/call': {
      const outcome = await callTool(gateway, access, params);
      if (outcome.kind === 'unauthorized') return unauthorized(gateway.publicUrl, true);
      if (outcome.kind === 'invalid') return jsonRpcError(id, JSON_RPC_INVALID_PARAMS, outcome.message);
      return jsonRpcResult(id, outcome.result);
    }
    default:
      return jsonRpcError(id, JSON_RPC_METHOD_NOT_FOUND, `Method not found: ${String(message.method)}`);
  }
}

export async function handleMcpRequest(request: Request, context: McpRequestContext): Promise<Response> {
  const { env } = context;
  if (env.MCP_ENABLED !== 'true') {
    return jsonError(404, 'route_not_found', 'The requested API route does not exist.');
  }
  if (request.method === 'OPTIONS') return corsPreflight(ALLOWED_METHODS);
  if (request.method !== 'POST') {
    return emptyMcpResponse(405, { allow: ALLOWED_METHODS });
  }
  const publicUrl = new URL(request.url);
  if (!env.MCP_RESOURCE || !env.RELAY_ISSUER || !env.RELAY_JWKS_URL || !env.RELAY_OBJECTS) {
    return jsonError(503, 'mcp_not_configured', 'The MCP endpoint is not configured.');
  }
  const token = mcpBearerToken(request);
  if (!token) return unauthorized(publicUrl, false);
  if (env.MCP_LIMITER) {
    const { success } = await env.MCP_LIMITER.limit({ key: `mcp:${await tokenHash(token)}` });
    if (!success) {
      return jsonRpcError(null, JSON_RPC_SERVER_ERROR, 'Too many requests. Try again shortly.', 429, {
        'retry-after': '60',
      });
    }
  }
  let access: McpAccess | null;
  try {
    access = await verifyMcpAccessToken(token, env, context.fetchJwks);
  } catch (error) {
    if (!(error instanceof RelayAuthorizationUnavailable)) throw error;
    return jsonError(503, 'mcp_authorization_unavailable', 'MCP authorization is temporarily unavailable.');
  }
  if (!access) return unauthorized(publicUrl, true);
  if (!access.scopes.has('mcp:read')) return insufficientScope(publicUrl);

  const text = await readBody(request);
  if (text === null) {
    return jsonRpcError(null, JSON_RPC_INVALID_REQUEST, 'The request body exceeds 1 MiB.', 413);
  }
  let message: unknown;
  try {
    message = JSON.parse(text);
  } catch {
    return jsonRpcError(null, JSON_RPC_PARSE_ERROR, 'The request body is not valid JSON.', 400);
  }
  if (Array.isArray(message)) {
    return jsonRpcError(null, JSON_RPC_INVALID_REQUEST, 'Batch requests are not supported.', 400);
  }
  if (!isJsonObject(message) || message.jsonrpc !== '2.0') {
    return jsonRpcError(null, JSON_RPC_INVALID_REQUEST, 'The request is not a JSON-RPC 2.0 message.', 400);
  }
  if (message.method === undefined && ('result' in message || 'error' in message)) {
    return emptyMcpResponse(202);
  }
  if (typeof message.method !== 'string') {
    return jsonRpcError(null, JSON_RPC_INVALID_REQUEST, 'The request method is missing.', 400);
  }
  if (!('id' in message)) return emptyMcpResponse(202);
  if (!validId(message.id)) {
    return jsonRpcError(null, JSON_RPC_INVALID_REQUEST, 'The request id must be a string or number.', 400);
  }
  const version = request.headers.get('mcp-protocol-version');
  if (
    message.method !== 'initialize' &&
    version !== null &&
    !(MCP_PROTOCOL_VERSIONS as readonly string[]).includes(version)
  ) {
    return jsonRpcError(message.id, JSON_RPC_INVALID_REQUEST, `Unsupported MCP protocol version: ${version}`, 400);
  }
  const gateway: GatewayContext = {
    env,
    fetchOrigin: context.fetchOrigin,
    authorization: `Bearer ${token}`,
    publicUrl,
    signal: request.signal,
    waitUntil: context.waitUntil,
  };
  return dispatch(message, message.id, access, gateway);
}
