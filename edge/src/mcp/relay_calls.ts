import type { RelayAttachment } from '../relay_authorization';
import { isJsonObject } from './protocol';

export const MCP_CLIENT_ID = '~mcp';
const MAX_FRAME_BYTES = 1024 * 1024;
const MAX_CALL_BODY_BYTES = 2 * MAX_FRAME_BYTES;
const MAX_TIMEOUT_MS = 10 * 60 * 1000;
const TIMEOUT_GRACE_MS = 5000;

export type RelayCallAnswer =
  | { ok: true; result: unknown }
  | { ok: false; code: string; message?: string };

interface PendingCall {
  socket: WebSocket;
  timer: ReturnType<typeof setTimeout>;
  resolve(answer: RelayCallAnswer): void;
}

interface CallRequest {
  callId: string;
  grant: string;
  tool: string;
  arguments: Record<string, unknown>;
  timeoutMs: number;
}

function boundedString(value: unknown, max: number): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= max;
}

function parseCallRequest(value: unknown): CallRequest | null {
  if (
    !isJsonObject(value) ||
    !boundedString(value.callId, 128) ||
    !boundedString(value.grant, 16384) ||
    !boundedString(value.tool, 128) ||
    !isJsonObject(value.arguments) ||
    !Number.isSafeInteger(value.timeoutMs) ||
    (value.timeoutMs as number) <= 0 ||
    (value.timeoutMs as number) > MAX_TIMEOUT_MS
  ) {
    return null;
  }
  return value as unknown as CallRequest;
}

export function mcpFrame(value: unknown): Uint8Array {
  const id = new TextEncoder().encode(MCP_CLIENT_ID);
  const json = new TextEncoder().encode(JSON.stringify(value));
  const bytes = new Uint8Array(2 + id.length + json.length);
  bytes[0] = (id.length >> 8) & 0xff;
  bytes[1] = id.length & 0xff;
  bytes.set(id, 2);
  bytes.set(json, 2 + id.length);
  return bytes;
}

function answer(value: RelayCallAnswer, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

/** Routes MCP calls over the runtime socket. Pending calls live in memory only, never in attachments. */
export class McpRelayCalls {
  private readonly pending = new Map<string, PendingCall>();

  constructor(
    private readonly runtimeSockets: () => WebSocket[],
    private readonly timeoutGraceMs = TIMEOUT_GRACE_MS,
  ) {}

  private liveRuntime(): WebSocket | null {
    const now = Math.floor(Date.now() / 1000);
    for (const socket of this.runtimeSockets()) {
      const attachment = socket.deserializeAttachment() as RelayAttachment;
      if (
        attachment.role === 'runtime' &&
        !attachment.suppressDisconnect &&
        attachment.exp > now &&
        (attachment.mcpAccess === 'read' || attachment.mcpAccess === 'full' || attachment.mcpAccess === 'admin')
      ) {
        return socket;
      }
    }
    return null;
  }

  async handle(request: Request): Promise<Response> {
    if (request.method !== 'POST') return answer({ ok: false, code: 'method_not_allowed' }, 405);
    let call: CallRequest | null = null;
    try {
      const text = await request.text();
      if (text.length <= MAX_CALL_BODY_BYTES) call = parseCallRequest(JSON.parse(text));
    } catch {
      call = null;
    }
    if (!call) return answer({ ok: false, code: 'invalid_call', message: 'The call request is invalid.' }, 400);
    if (this.pending.has(call.callId)) {
      return answer({ ok: false, code: 'duplicate_call', message: 'The call is already in flight.' });
    }
    const socket = this.liveRuntime();
    if (!socket) return answer({ ok: false, code: 'runtime_offline', message: 'The runtime is not connected.' });
    const frame = mcpFrame({
      type: 'mcp.call',
      id: call.callId,
      grant: call.grant,
      tool: call.tool,
      arguments: call.arguments,
      timeoutMs: call.timeoutMs,
    });
    if (frame.byteLength > MAX_FRAME_BYTES) {
      return answer({ ok: false, code: 'payload_too_large', message: 'The tool arguments exceed 1 MiB.' });
    }
    return answer(await this.dispatch(socket, call, frame, request.signal));
  }

  private dispatch(
    socket: WebSocket,
    call: CallRequest,
    frame: Uint8Array,
    signal: AbortSignal | undefined,
  ): Promise<RelayCallAnswer> {
    const { callId } = call;
    return new Promise<RelayCallAnswer>((resolve) => {
      const onAbort = () => {
        this.cancel(callId);
        this.settle(callId, { ok: false, code: 'cancelled', message: 'The caller went away.' });
      };
      const timer = setTimeout(() => {
        this.cancel(callId);
        this.settle(callId, { ok: false, code: 'timeout', message: 'The runtime did not answer in time.' });
      }, call.timeoutMs + this.timeoutGraceMs);
      this.pending.set(callId, {
        socket,
        timer,
        resolve: (value) => {
          signal?.removeEventListener('abort', onAbort);
          resolve(value);
        },
      });
      if (signal?.aborted) return onAbort();
      signal?.addEventListener('abort', onAbort);
      try {
        socket.send(frame);
      } catch {
        this.settle(callId, { ok: false, code: 'runtime_offline', message: 'The runtime link failed.' });
      }
    });
  }

  private cancel(callId: string): void {
    const pending = this.pending.get(callId);
    if (!pending) return;
    try {
      pending.socket.send(mcpFrame({ type: 'mcp.cancel', id: callId }));
    } catch {
      // The socket is already gone; the runtime cancels its own calls when the link drops.
    }
  }

  private settle(callId: string, value: RelayCallAnswer): void {
    const pending = this.pending.get(callId);
    if (!pending) return;
    this.pending.delete(callId);
    clearTimeout(pending.timer);
    pending.resolve(value);
  }

  /** Handles a `~mcp` frame sent by the runtime socket. */
  handleRuntimeFrame(socket: WebSocket, bytes: Uint8Array): void {
    const payload = bytes.subarray(2 + ((bytes[0] << 8) | bytes[1]));
    let text: string;
    try {
      text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(payload);
    } catch {
      return;
    }
    let message: unknown;
    try {
      message = JSON.parse(text);
    } catch {
      const id = /"id"\s*:\s*"((?:[^"\\]|\\.){1,128})"/.exec(text.slice(0, 512))?.[1];
      if (id) {
        this.settleFrom(socket, id, {
          ok: false,
          code: 'invalid_result',
          message: 'The runtime sent an unreadable result.',
        });
      }
      return;
    }
    if (!isJsonObject(message) || typeof message.id !== 'string') return;
    if (message.type !== 'mcp.result') return;
    if (isJsonObject(message.error)) {
      const { code, message: detail } = message.error;
      this.settleFrom(socket, message.id, {
        ok: false,
        code: typeof code === 'string' && code ? code : 'runtime_error',
        message: typeof detail === 'string' ? detail : undefined,
      });
      return;
    }
    if (message.result === undefined) {
      this.settleFrom(socket, message.id, {
        ok: false,
        code: 'invalid_result',
        message: 'The runtime sent a result without content.',
      });
      return;
    }
    this.settleFrom(socket, message.id, { ok: true, result: message.result });
  }

  private settleFrom(socket: WebSocket, callId: string, value: RelayCallAnswer): void {
    if (this.pending.get(callId)?.socket === socket) this.settle(callId, value);
  }

  /** Rejects every call routed through a runtime socket that closed or was replaced. */
  settleSocket(socket: WebSocket): void {
    for (const [callId, pending] of this.pending) {
      if (pending.socket === socket) {
        this.settle(callId, { ok: false, code: 'runtime_offline', message: 'The runtime disconnected.' });
      }
    }
  }
}
