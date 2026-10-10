export const MCP_PATH = '/v1/mcp';
export const MCP_SERVER_VERSION = '0.1.0';
export const MCP_PROTOCOL_VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26'] as const;
export const MCP_SCOPES = 'mcp:read mcp:execute mcp:admin';
export const MAX_MCP_BODY_BYTES = 1024 * 1024;

export const MCP_INSTRUCTIONS =
  'Alera controls coding workspaces, terminals, and agents on the runtimes this connection was granted. ' +
  'Call list_runtimes first to see which runtimes are online. Every other tool accepts an optional ' +
  '`runtime` argument (runtime name or id); pass it whenever more than one runtime is online. ' +
  'Nothing is remembered between calls, so name the runtime on each call.';

export const JSON_RPC_PARSE_ERROR = -32700;
export const JSON_RPC_INVALID_REQUEST = -32600;
export const JSON_RPC_METHOD_NOT_FOUND = -32601;
export const JSON_RPC_INVALID_PARAMS = -32602;
export const JSON_RPC_SERVER_ERROR = -32000;

export type JsonRpcId = string | number;

export const CORS_HEADERS: Record<string, string> = {
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type, mcp-protocol-version, mcp-session-id',
  'access-control-expose-headers': 'www-authenticate, mcp-session-id',
  'access-control-max-age': '86400',
};

export function corsPreflight(methods: string): Response {
  return new Response(null, {
    status: 204,
    headers: { ...CORS_HEADERS, 'access-control-allow-methods': methods },
  });
}

export function mcpHeaders(extra: Record<string, string> = {}): Headers {
  return new Headers({
    ...CORS_HEADERS,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...extra,
  });
}

function jsonRpcResponse(body: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: mcpHeaders({ 'content-type': 'application/json; charset=utf-8', ...extra }),
  });
}

export function jsonRpcResult(id: JsonRpcId, result: unknown): Response {
  return jsonRpcResponse({ jsonrpc: '2.0', id, result }, 200);
}

export function jsonRpcError(
  id: JsonRpcId | null,
  code: number,
  message: string,
  status = 200,
  extra: Record<string, string> = {},
): Response {
  return jsonRpcResponse({ jsonrpc: '2.0', id, error: { code, message } }, status, extra);
}

export function emptyMcpResponse(status: number, extra: Record<string, string> = {}): Response {
  return new Response(null, { status, headers: mcpHeaders(extra) });
}

export function negotiateProtocolVersion(requested: unknown): string {
  return typeof requested === 'string' &&
    (MCP_PROTOCOL_VERSIONS as readonly string[]).includes(requested)
    ? requested
    : MCP_PROTOCOL_VERSIONS[0];
}

export function isJsonObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export interface ToolResult {
  content: Array<Record<string, unknown>>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}

export function toolError(message: string): ToolResult {
  return { content: [{ type: 'text', text: message }], isError: true };
}

export function toolJson(value: Record<string, unknown>): ToolResult {
  return { content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value };
}

/** Accepts only the CallToolResult shape so a runtime cannot inject arbitrary JSON-RPC fields. */
export function validToolResult(value: unknown): ToolResult | null {
  if (!isJsonObject(value) || !Array.isArray(value.content)) return null;
  if (!value.content.every((item) => isJsonObject(item) && typeof item.type === 'string')) return null;
  if (value.structuredContent !== undefined && !isJsonObject(value.structuredContent)) return null;
  if (value.isError !== undefined && typeof value.isError !== 'boolean') return null;
  const result: ToolResult = { content: value.content as Array<Record<string, unknown>> };
  if (value.structuredContent !== undefined) result.structuredContent = value.structuredContent;
  if (value.isError !== undefined) result.isError = value.isError;
  return result;
}
