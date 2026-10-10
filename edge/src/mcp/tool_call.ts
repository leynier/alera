import { originRequest, type EdgeEnvironment, type OriginFetch } from '../index';
import type { McpAccess } from './access_token';
import { isJsonObject, toolError, toolJson, validToolResult, type ToolResult } from './protocol';
import { LIST_RUNTIMES_TOOL, RUNTIME_TOOLS, type CatalogTool } from './tools';

export interface GatewayContext {
  env: EdgeEnvironment;
  fetchOrigin: OriginFetch;
  authorization: string;
  publicUrl: URL;
  signal: AbortSignal;
  waitUntil(promise: Promise<unknown>): void;
}

export type ToolCallOutcome =
  | { kind: 'result'; result: ToolResult }
  | { kind: 'invalid'; message: string }
  | { kind: 'unauthorized' };

type CallOutcomeName = 'ok' | 'tool_error' | 'runtime_offline' | 'timeout' | 'failed';

export interface GatewayResponse {
  status: number;
  body: Record<string, unknown> | null;
}

interface CallGrant {
  callId: string;
  runtimeId: string;
  runtimeName: string;
  grant: string;
}

const RELAY_CALL_URL = 'https://relay.internal/mcp/call';

export async function gateway(
  context: GatewayContext,
  method: 'GET' | 'POST' | 'DELETE',
  path: string,
  body?: unknown,
): Promise<GatewayResponse> {
  const url = new URL(path, context.publicUrl.origin);
  const headers = new Headers({ accept: 'application/json', authorization: context.authorization });
  if (body !== undefined) headers.set('content-type', 'application/json');
  const request = new Request(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: context.signal,
  });
  const response = await context.fetchOrigin(originRequest(request, context.env, url));
  let parsed: unknown = null;
  try {
    parsed = await response.json();
  } catch {
    parsed = null;
  }
  return { status: response.status, body: isJsonObject(parsed) ? parsed : null };
}

function gatewayFailure(response: GatewayResponse): string {
  const error = isJsonObject(response.body?.error) ? response.body.error : null;
  const code = typeof error?.code === 'string' ? error.code : `http_${response.status}`;
  const message = typeof error?.message === 'string' ? error.message : 'The Alera service refused the call.';
  return `${code}: ${message}`;
}

function callGrant(body: Record<string, unknown> | null): CallGrant | null {
  if (
    !body ||
    typeof body.callId !== 'string' ||
    !body.callId ||
    typeof body.runtimeId !== 'string' ||
    !body.runtimeId ||
    typeof body.grant !== 'string' ||
    !body.grant
  ) {
    return null;
  }
  return {
    callId: body.callId,
    runtimeId: body.runtimeId,
    runtimeName: typeof body.runtimeName === 'string' ? body.runtimeName : body.runtimeId,
    grant: body.grant,
  };
}

async function listRuntimes(context: GatewayContext): Promise<ToolCallOutcome> {
  let response: GatewayResponse;
  try {
    response = await gateway(context, 'GET', '/v1/mcp/runtimes');
  } catch {
    return { kind: 'result', result: toolError('The Alera service is temporarily unavailable.') };
  }
  if (response.status === 401) return { kind: 'unauthorized' };
  if (response.status < 200 || response.status >= 300 || !response.body) {
    return { kind: 'result', result: toolError(gatewayFailure(response)) };
  }
  return { kind: 'result', result: toolJson(response.body) };
}

function recordOutcome(
  context: GatewayContext,
  callId: string,
  outcome: CallOutcomeName,
  durationMs: number,
): void {
  const path = `/v1/mcp/calls/${encodeURIComponent(callId)}/outcome`;
  // The audit write must survive the client disconnecting, so it does not share the request signal.
  const detached = { ...context, signal: AbortSignal.timeout(10000) };
  context.waitUntil(
    gateway(detached, 'POST', path, { outcome, durationMs }).catch(() => undefined),
  );
}

interface RelayAnswer {
  outcome: CallOutcomeName;
  result: ToolResult;
}

async function callRuntime(
  context: GatewayContext,
  tool: CatalogTool,
  grant: CallGrant,
  args: Record<string, unknown>,
): Promise<RelayAnswer> {
  const relay = context.env.RELAY_OBJECTS!;
  let answer: unknown;
  try {
    const response = await relay.get(relay.idFromName(grant.runtimeId)).fetch(RELAY_CALL_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        callId: grant.callId,
        grant: grant.grant,
        tool: tool.name,
        arguments: args,
        timeoutMs: tool.timeoutSeconds * 1000,
      }),
      signal: context.signal,
    });
    answer = await response.json();
  } catch {
    return { outcome: 'failed', result: toolError('The runtime link is temporarily unavailable.') };
  }
  if (!isJsonObject(answer)) {
    return { outcome: 'failed', result: toolError('The runtime link returned an invalid answer.') };
  }
  if (answer.ok === true) {
    const result = validToolResult(answer.result);
    if (!result) return { outcome: 'failed', result: toolError('The runtime returned an invalid tool result.') };
    return { outcome: result.isError ? 'tool_error' : 'ok', result };
  }
  const code = typeof answer.code === 'string' ? answer.code : 'failed';
  const message = typeof answer.message === 'string' ? answer.message : '';
  if (code === 'runtime_offline') {
    return {
      outcome: 'runtime_offline',
      result: toolError(
        `runtime_offline: Runtime "${grant.runtimeName}" is not connected with MCP Control enabled. Check that it is running and try again.`,
      ),
    };
  }
  if (code === 'timeout') {
    return {
      outcome: 'timeout',
      result: toolError(
        `timeout: Runtime "${grant.runtimeName}" did not answer within ${tool.timeoutSeconds} seconds.`,
      ),
    };
  }
  return {
    outcome: 'failed',
    result: toolError(`${code}: ${message || 'The runtime could not run the tool.'}`),
  };
}

export async function callTool(
  context: GatewayContext,
  access: McpAccess,
  params: Record<string, unknown>,
): Promise<ToolCallOutcome> {
  if (typeof params.name !== 'string') return { kind: 'invalid', message: 'The tool name is required.' };
  if (params.arguments !== undefined && !isJsonObject(params.arguments)) {
    return { kind: 'invalid', message: 'Tool arguments must be an object.' };
  }
  if (params.name === LIST_RUNTIMES_TOOL) return listRuntimes(context);
  const tool = RUNTIME_TOOLS.get(params.name);
  if (!tool) return { kind: 'invalid', message: `Unknown tool: ${params.name}` };
  if (tool.access === 'execute' && !access.scopes.has('mcp:execute')) {
    return {
      kind: 'result',
      result: toolError(
        `insufficient_scope: ${tool.name} needs the mcp:execute scope, but this connection was granted read access only. Reconnect Alera and allow execute access.`,
      ),
    };
  }
  if (tool.access === 'admin' && !access.scopes.has('mcp:admin')) {
    return {
      kind: 'result',
      result: toolError(
        `insufficient_scope: ${tool.name} needs the mcp:admin scope, but this connection was not granted administrative tools. Reconnect Alera and allow administrative tools.`,
      ),
    };
  }
  const { runtime, ...args } = (params.arguments ?? {}) as Record<string, unknown>;
  if (runtime !== undefined && (typeof runtime !== 'string' || !runtime.trim())) {
    return { kind: 'result', result: toolError('The runtime argument must be a runtime name or id.') };
  }
  let response: GatewayResponse;
  try {
    response = await gateway(context, 'POST', '/v1/mcp/calls', {
      ...(runtime === undefined ? {} : { runtime }),
      tool: tool.name,
      access: tool.access,
    });
  } catch {
    return { kind: 'result', result: toolError('The Alera service is temporarily unavailable.') };
  }
  if (response.status === 401) return { kind: 'unauthorized' };
  if (response.status < 200 || response.status >= 300) {
    return { kind: 'result', result: toolError(gatewayFailure(response)) };
  }
  const grant = callGrant(response.body);
  if (!grant) {
    return { kind: 'result', result: toolError('The Alera service returned an invalid call grant.') };
  }
  const started = Date.now();
  const answer = await callRuntime(context, tool, grant, args);
  recordOutcome(context, grant.callId, answer.outcome, Date.now() - started);
  return { kind: 'result', result: answer.result };
}
