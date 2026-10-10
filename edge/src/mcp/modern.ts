import type { EdgeEnvironment } from '../index';
import { eventsEnabled } from './events';
import {
  isJsonObject,
  jsonRpcError,
  JSON_RPC_HEADER_MISMATCH,
  JSON_RPC_UNSUPPORTED_VERSION,
  MCP_INSTRUCTIONS,
  MCP_MODERN_PROTOCOL_VERSION,
  MCP_SERVER_VERSION,
  MCP_SUPPORTED_VERSIONS,
  type JsonRpcId,
} from './protocol';

/**
 * MCP 2026-07-28 support next to the handshake-based versions. A modern request carries
 * its version in `params._meta` and the `MCP-Protocol-Version` header; legacy clients keep
 * sending `initialize` and are served exactly as before.
 */

const META_VERSION = 'io.modelcontextprotocol/protocolVersion';
const SERVER_INFO = { name: 'alera', title: 'Alera', version: MCP_SERVER_VERSION };

export interface RequestEra {
  version: string | null;
  modern: boolean;
}

function decodeHeader(value: string): string | null {
  const match = /^=\?base64\?(.*)\?=$/.exec(value);
  if (!match) return value;
  try {
    const bytes = Uint8Array.from(atob(match[1]), (char) => char.charCodeAt(0));
    return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    return null;
  }
}

function mismatch(id: JsonRpcId, detail: string): Response {
  return jsonRpcError(id, JSON_RPC_HEADER_MISMATCH, `Header mismatch: ${detail}`, 400);
}

/** Reads the request's protocol version, or returns the 400 response that rejects it. */
export function requestEra(message: Record<string, unknown>, id: JsonRpcId, headers: Headers): RequestEra | Response {
  const header = headers.get('mcp-protocol-version');
  const params = isJsonObject(message.params) ? message.params : {};
  const meta = isJsonObject(params._meta) ? params._meta : {};
  const metaVersion = typeof meta[META_VERSION] === 'string' ? (meta[META_VERSION] as string) : null;
  if (header !== null && metaVersion !== null && header !== metaVersion) {
    return mismatch(id, 'MCP-Protocol-Version does not match _meta.');
  }
  const version = metaVersion ?? header;
  // The legacy handshake negotiates its version in the body.
  if (message.method === 'initialize') return { version, modern: false };
  if (version !== null && !MCP_SUPPORTED_VERSIONS.includes(version)) {
    return jsonRpcError(id, JSON_RPC_UNSUPPORTED_VERSION, 'Unsupported protocol version', 400, {}, {
      supported: [...MCP_SUPPORTED_VERSIONS],
      requested: version,
    });
  }
  const modern = version === MCP_MODERN_PROTOCOL_VERSION;
  if (modern) {
    const method = headers.get('mcp-method');
    if (method !== null && method !== message.method) return mismatch(id, 'Mcp-Method does not match the body.');
    const name = headers.get('mcp-name');
    const target = typeof params.name === 'string' ? params.name : typeof params.uri === 'string' ? params.uri : null;
    if (name !== null && target !== null && decodeHeader(name) !== target) {
      return mismatch(id, 'Mcp-Name does not match the body.');
    }
  }
  return { version, modern };
}

/** The `server/discover` result. `events` is advertised only while MCP Events is on. */
export function discoverResult(env: EdgeEnvironment): Record<string, unknown> {
  const capabilities: Record<string, unknown> = { tools: { listChanged: false } };
  if (eventsEnabled(env)) capabilities.events = {};
  return {
    resultType: 'complete',
    supportedVersions: [...MCP_SUPPORTED_VERSIONS],
    capabilities,
    serverInfo: SERVER_INFO,
    _meta: { 'io.modelcontextprotocol/serverInfo': SERVER_INFO },
    instructions: MCP_INSTRUCTIONS,
  };
}
