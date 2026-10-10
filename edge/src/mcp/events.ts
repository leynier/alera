import type { EdgeEnvironment } from '../index';
import catalog from './event_catalog.json';
import {
  isJsonObject,
  JSON_RPC_CALLBACK_ENDPOINT_ERROR,
  JSON_RPC_FORBIDDEN,
  JSON_RPC_INTERNAL_ERROR,
  JSON_RPC_INVALID_PARAMS,
  JSON_RPC_METHOD_NOT_FOUND,
} from './protocol';
import { gateway, type GatewayContext, type GatewayResponse } from './tool_call';

/**
 * OpenAI MCP Events (`events/list`, `events/subscribe`, `events/unsubscribe`). The edge
 * checks the request shape; the cloud verifies the callback, stores the subscription
 * bound to the grant, and delivers signed webhooks.
 */

export interface EventDefinition {
  name: string;
  description: string;
  delivery: string[];
  inputSchema: { properties: Record<string, unknown> };
  payloadSchema: Record<string, unknown>;
}

export const EVENT_DEFINITIONS: EventDefinition[] = (catalog as { events: EventDefinition[] }).events;
const EVENT_NAMES = new Set(EVENT_DEFINITIONS.map((event) => event.name));
const SUBSCRIPTIONS_PATH = '/v1/mcp/event-subscriptions';
const CALLBACK_REASONS = new Set([
  'challenge_failed',
  'timeout',
  'invalid_url',
  'dns_failed',
  'non_public_destination',
  'connection_failed',
  'response_too_large',
]);

export type EventOutcome =
  | { kind: 'result'; result: Record<string, unknown> }
  | { kind: 'error'; code: number; message: string; data?: Record<string, unknown> }
  | { kind: 'unauthorized' };

export function eventsEnabled(env: EdgeEnvironment): boolean {
  return env.MCP_EVENTS_ENABLED === 'true';
}

function invalid(message: string): EventOutcome {
  return { kind: 'error', code: JSON_RPC_INVALID_PARAMS, message };
}

export function listEvents(params: Record<string, unknown>): EventOutcome {
  if (params.cursor !== undefined && params.cursor !== null) {
    return invalid('The event catalog has one page; omit cursor.');
  }
  return { kind: 'result', result: { events: EVENT_DEFINITIONS } };
}

function shortString(value: unknown, max: number): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= max;
}

/** Shared checks for subscribe and unsubscribe. Returns an error outcome or null. */
function checkIdentity(params: Record<string, unknown>, needsSecret: boolean): EventOutcome | null {
  if (typeof params.name !== 'string' || !EVENT_NAMES.has(params.name)) {
    return invalid('Unknown event name. Call events/list for the catalog.');
  }
  if (params.arguments !== undefined && !isJsonObject(params.arguments)) {
    return invalid('arguments must be an object.');
  }
  const definition = EVENT_DEFINITIONS.find((event) => event.name === params.name);
  const allowed = new Set(Object.keys(definition?.inputSchema.properties ?? {}));
  for (const [key, value] of Object.entries((params.arguments as Record<string, unknown>) ?? {})) {
    if (!allowed.has(key) || !shortString(value, 128)) return invalid(`Invalid argument ${key}.`);
  }
  const delivery = params.delivery;
  if (!isJsonObject(delivery) || delivery.mode !== 'webhook' || !shortString(delivery.url, 2048)) {
    return invalid('delivery must be { mode: "webhook", url }.');
  }
  if (needsSecret && !shortString(delivery.secret, 256)) {
    return invalid('delivery.secret must be a whsec_ signing secret.');
  }
  return null;
}

function failure(response: GatewayResponse): EventOutcome {
  if (response.status === 401) return { kind: 'unauthorized' };
  const error = isJsonObject(response.body?.error) ? response.body.error : null;
  const code = typeof error?.code === 'string' ? error.code : '';
  const message = typeof error?.message === 'string' ? error.message : 'The Alera service refused the request.';
  if (code === 'callback_endpoint_error') {
    const reason = CALLBACK_REASONS.has(message) ? message : 'verification_failed';
    return {
      kind: 'error',
      code: JSON_RPC_CALLBACK_ENDPOINT_ERROR,
      message: 'CallbackEndpointError',
      data: { reason },
    };
  }
  if (code === 'mcp_events_disabled') {
    return { kind: 'error', code: JSON_RPC_METHOD_NOT_FOUND, message: 'MCP Events are not enabled.' };
  }
  if (response.status === 400 || response.status === 404 || response.status === 409) {
    return invalid(code ? `${code}: ${message}` : message);
  }
  if (response.status === 403) return { kind: 'error', code: JSON_RPC_FORBIDDEN, message };
  return { kind: 'error', code: JSON_RPC_INTERNAL_ERROR, message: 'Event subscriptions are temporarily unavailable.' };
}

async function forward(context: GatewayContext, path: string, body: unknown): Promise<GatewayResponse | null> {
  try {
    return await gateway(context, 'POST', path, body);
  } catch {
    return null;
  }
}

export async function subscribeEvent(
  context: GatewayContext,
  params: Record<string, unknown>,
): Promise<EventOutcome> {
  const problem = checkIdentity(params, true);
  if (problem) return problem;
  if (params.cursor !== undefined && params.cursor !== null && !shortString(params.cursor, 1024)) {
    return invalid('cursor must be a string or null.');
  }
  const ttl = params.ttlMs;
  if (ttl !== undefined && ttl !== null && !(Number.isSafeInteger(ttl) && (ttl as number) > 0)) {
    return invalid('ttlMs must be a positive integer or null.');
  }
  const delivery = params.delivery as Record<string, unknown>;
  const response = await forward(context, SUBSCRIPTIONS_PATH, {
    name: params.name,
    arguments: params.arguments ?? {},
    delivery: { mode: 'webhook', url: delivery.url, secret: delivery.secret },
    cursor: params.cursor ?? null,
    ttlMs: ttl ?? null,
  });
  if (!response) return { kind: 'error', code: JSON_RPC_INTERNAL_ERROR, message: 'The Alera service is unavailable.' };
  if (response.status !== 200 || !response.body || typeof response.body.id !== 'string') return failure(response);
  const { id, refreshBefore, cursor, truncated } = response.body;
  return { kind: 'result', result: { id, refreshBefore, cursor, truncated: truncated === true } };
}

export async function unsubscribeEvent(
  context: GatewayContext,
  params: Record<string, unknown>,
): Promise<EventOutcome> {
  const problem = checkIdentity(params, false);
  if (problem) return problem;
  const delivery = params.delivery as Record<string, unknown>;
  const response = await forward(context, `${SUBSCRIPTIONS_PATH}/unsubscribe`, {
    name: params.name,
    arguments: params.arguments ?? {},
    delivery: { mode: 'webhook', url: delivery.url },
  });
  if (!response) return { kind: 'error', code: JSON_RPC_INTERNAL_ERROR, message: 'The Alera service is unavailable.' };
  if (response.status !== 204 && response.status !== 200) return failure(response);
  return { kind: 'result', result: {} };
}
