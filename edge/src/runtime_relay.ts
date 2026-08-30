import type { EdgeEnvironment } from './index';
import {
  base64UrlBytes,
  verifyRelayGrant,
  sameRelayIdentity,
  controlFrame,
  RELAY_CONTROL_PROTOCOL,
  RelayAuthorizationUnavailable,
  type RelayAttachment,
  type RelayFetch,
} from './relay_authorization';
import {
  jsonError,
  isWebSocketUpgrade,
  relayFrameClientId,
  relayDisconnectFrame,
  originRequest,
} from './index';
const MAX_RELAY_FRAME_BYTES = 1024 * 1024;
const MAX_RELAY_MOBILE_CONNECTIONS = 8;
export class RuntimeRelayDurableObject {
  private readonly ctx: DurableObjectState;
  private readonly renewing = new WeakSet<WebSocket>();

  constructor(
    ctx: DurableObjectState,
    private readonly env?: EdgeEnvironment,
    private readonly fetchJwks?: RelayFetch,
  ) {
    this.ctx = ctx;
  }

  async fetch(request: Request): Promise<Response> {
    if (!isWebSocketUpgrade(request)) {
      return jsonError(426, 'websocket_required', 'The relay requires a WebSocket connection.');
    }
    const encoded = request.headers.get('x-alera-relay-claims');
    if (!encoded) return jsonError(403, 'missing_relay_claims', 'Relay claims are missing.');
    let attachment: RelayAttachment;
    try {
      const bytes = base64UrlBytes(encoded);
      attachment = JSON.parse(new TextDecoder().decode(bytes)) as RelayAttachment;
    } catch {
      return jsonError(403, 'invalid_relay_claims', 'Relay claims are invalid.');
    }
    const peers = this.ctx.getWebSockets();
    const peerAttachments = peers.map((peer) => peer.deserializeAttachment() as RelayAttachment);
    if (
      attachment.role === 'mobile' &&
      !peerAttachments.some(
        (peer) =>
          peer.role === 'runtime' &&
          !peer.suppressDisconnect &&
          peer.exp > Math.floor(Date.now() / 1000) &&
          peer.accountId === attachment.accountId &&
          peer.runtimeId === attachment.runtimeId,
      )
    ) {
      return jsonError(503, 'relay_runtime_unavailable', 'The runtime is reconnecting. Try again shortly.');
    }
    const replacingDuplicate = peerAttachments.some(
      (peer) => peer.role === attachment.role && peer.clientId === attachment.clientId,
    );
    for (const peer of peers) {
      const peerAttachment = peer.deserializeAttachment() as RelayAttachment;
      if (peerAttachment.role === attachment.role && peerAttachment.clientId === attachment.clientId) {
        if (peerAttachment.role === 'mobile') {
          peer.serializeAttachment({
            ...peerAttachment,
            suppressDisconnect: true,
          });
          this.notifyRuntimeOfMobileDisconnect(peerAttachment);
        } else {
          peer.serializeAttachment({
            ...peerAttachment,
            suppressDisconnect: true,
          });
          this.disconnectMobilesForRuntime(peerAttachment);
        }
        peer.close(
          4001,
          attachment.role === 'runtime'
            ? 'replaced by a newer runtime'
            : 'replaced by a newer mobile connection',
        );
      }
    }
    if (
      attachment.role === 'mobile' &&
      peerAttachments.filter(
        (peer) =>
          peer.role === 'mobile' && !peer.suppressDisconnect && peer.exp > Math.floor(Date.now() / 1000),
      ).length >= MAX_RELAY_MOBILE_CONNECTIONS &&
      !replacingDuplicate
    ) {
      return jsonError(429, 'relay_mobile_limit', 'This runtime has reached its mobile connection limit.');
    }
    const webSocketPair = new WebSocketPair();
    const [client, server] = Object.values(webSocketPair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server, [attachment.role, attachment.clientId]);
    server.serializeAttachment({
      ...attachment,
      connectionId: attachment.jti,
      awaitingRuntime:
        attachment.role === 'mobile' &&
        attachment.controlProtocol === true &&
        peerAttachments.some(
          (peer) => peer.role === 'runtime' && !peer.suppressDisconnect && peer.controlProtocol,
        ),
    });
    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: attachment.controlProtocol ? { 'sec-websocket-protocol': RELAY_CONTROL_PROTOCOL } : undefined,
    });
  }

  webSocketMessage(socket: WebSocket, message: ArrayBuffer | string): void | Promise<void> {
    const bytes = typeof message === 'string' ? new TextEncoder().encode(message) : new Uint8Array(message);
    if (bytes.byteLength > MAX_RELAY_FRAME_BYTES) {
      socket.close(1009, 'relay frame too large');
      return;
    }
    const sender = socket.deserializeAttachment() as RelayAttachment;
    if (sender.suppressDisconnect) return;
    const now = Math.floor(Date.now() / 1000);
    if (sender.exp <= now) {
      socket.close(4003, 'relay grant expired');
      return;
    }
    if (bytes.length >= 2 && bytes[0] === 0 && bytes[1] === 0) {
      if (sender.controlProtocol && sender.role === 'runtime' && bytes.length <= 16384) {
        try {
          const command = JSON.parse(new TextDecoder().decode(bytes.subarray(2)));
          if (['peer.close', 'peer.ready'].includes(command.type) && typeof command.clientId === 'string') {
            for (const peer of this.ctx.getWebSockets('mobile')) {
              const target = peer.deserializeAttachment() as RelayAttachment;
              if (
                !target.suppressDisconnect &&
                target.role === 'mobile' &&
                target.clientId === command.clientId &&
                (target.connectionId ?? target.jti) === command.connectionId &&
                target.runtimeId === sender.runtimeId &&
                target.accountId === sender.accountId
              ) {
                if (command.type === 'peer.ready') {
                  peer.serializeAttachment({
                    ...target,
                    awaitingRuntime: false,
                  });
                  continue;
                }
                peer.serializeAttachment({
                  ...target,
                  suppressDisconnect: true,
                });
                peer.close(
                  command.code === 4004 ? 4004 : 1013,
                  command.code === 4004
                    ? 'relay authorization or protocol rejected'
                    : 'relay peer unavailable',
                );
              }
            }
            return;
          }
        } catch {
          socket.close(1007, 'invalid relay control');
          return;
        }
      }
      return this.renewAuthorization(socket, sender, bytes);
    }
    const clientId = relayFrameClientId(bytes);
    if (!clientId) {
      socket.close(1007, 'invalid relay frame');
      return;
    }
    if (sender.role === 'mobile' && sender.clientId !== clientId) {
      socket.close(1008, 'relay client id mismatch');
      return;
    }
    for (const peer of this.ctx.getWebSockets()) {
      if (peer === socket) continue;
      const target = peer.deserializeAttachment() as RelayAttachment;
      if (target.suppressDisconnect || target.awaitingRuntime) continue;
      if (target.exp <= now) {
        peer.close(4003, 'relay grant expired');
        continue;
      }
      if (
        sender.role === target.role ||
        sender.accountId !== target.accountId ||
        sender.runtimeId !== target.runtimeId ||
        (sender.role === 'runtime' && target.clientId !== clientId)
      ) {
        continue;
      }
      try {
        peer.send(bytes);
      } catch {
        peer.close(1011, 'relay forwarding failed');
      }
    }
  }

  private async renewAuthorization(
    socket: WebSocket,
    previous: RelayAttachment,
    bytes: Uint8Array,
  ): Promise<void> {
    if (previous.controlProtocol && this.env?.RELAY_RENEWAL_ENABLED === 'false') {
      socket.close(1012, 'relay renewal disabled; reconnect');
      return;
    }
    if (!previous.controlProtocol || !this.env || bytes.length > 16384) {
      socket.close(1008, 'relay renewal unavailable');
      return;
    }
    if (this.renewing.has(socket)) return;
    this.renewing.add(socket);
    let requestId: number | undefined;
    try {
      const request = JSON.parse(
        new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes.subarray(2)),
      ) as { type?: string; id?: number; grant?: string };
      if (
        request.type !== 'auth.renew' ||
        !Number.isSafeInteger(request.id) ||
        typeof request.grant !== 'string'
      ) {
        socket.close(1007, 'invalid relay control');
        return;
      }
      requestId = request.id;
      const env = this.env;
      const fetcher =
        this.fetchJwks ?? ((request: Request) => fetch(originRequest(request, env, new URL(request.url))));
      const claims = await verifyRelayGrant(request.grant, env, fetcher);
      const current = socket.deserializeAttachment() as RelayAttachment;
      // Verification yields. A close or replacement while it runs must win.
      if (current.suppressDisconnect || current.jti !== previous.jti) return;
      if (current.exp <= Math.floor(Date.now() / 1000)) {
        socket.close(4003, 'relay grant expired');
        return;
      }
      if (
        !claims ||
        !sameRelayIdentity(previous, claims) ||
        (claims.jti !== previous.jti && claims.exp <= previous.exp)
      ) {
        socket.send(
          controlFrame({
            type: 'auth.error',
            id: request.id,
            code: 'invalid_relay_grant',
          }),
        );
        return;
      }
      socket.serializeAttachment({
        ...claims,
        controlProtocol: true,
        connectionId: previous.connectionId ?? previous.jti,
        awaitingRuntime: previous.awaitingRuntime,
      });
      socket.send(
        controlFrame({
          type: 'auth.renewed',
          id: request.id,
          expiresAt: claims.exp,
        }),
      );
    } catch (error) {
      const current = socket.deserializeAttachment() as RelayAttachment;
      if (current.suppressDisconnect || current.jti !== previous.jti) return;
      if (error instanceof RelayAuthorizationUnavailable) {
        socket.send(
          controlFrame({
            type: 'auth.error',
            id: requestId,
            code: 'relay_authorization_unavailable',
          }),
        );
      } else {
        socket.close(1007, 'invalid relay control');
      }
    } finally {
      this.renewing.delete(socket);
    }
  }

  webSocketClose(socket: WebSocket): void {
    this.handlePeerDisconnectOnce(socket);
  }

  webSocketError(socket: WebSocket): void {
    this.handlePeerDisconnectOnce(socket);
  }

  private handlePeerDisconnectOnce(socket: WebSocket): void {
    const peer = socket.deserializeAttachment() as RelayAttachment;
    if (peer.suppressDisconnect) return;
    socket.serializeAttachment({ ...peer, suppressDisconnect: true });
    if (peer.role === 'mobile') {
      this.notifyRuntimeOfMobileDisconnect(peer);
    } else {
      this.disconnectMobilesForRuntime(peer);
    }
  }

  private notifyRuntimeOfMobileDisconnect(mobile: RelayAttachment): void {
    if (mobile.role !== 'mobile') return;
    const frame = relayDisconnectFrame(mobile.clientId);
    for (const peer of this.ctx.getWebSockets('runtime')) {
      const runtime = peer.deserializeAttachment() as RelayAttachment;
      if (runtime.suppressDisconnect) continue;
      if (runtime.accountId !== mobile.accountId || runtime.runtimeId !== mobile.runtimeId) continue;
      try {
        peer.send(frame);
      } catch {
        peer.close(1011, 'relay forwarding failed');
      }
    }
  }

  private disconnectMobilesForRuntime(runtime: RelayAttachment): void {
    if (runtime.role !== 'runtime') return;
    for (const peer of this.ctx.getWebSockets('mobile')) {
      const mobile = peer.deserializeAttachment() as RelayAttachment;
      if (
        mobile.role !== 'mobile' ||
        mobile.accountId !== runtime.accountId ||
        mobile.runtimeId !== runtime.runtimeId
      ) {
        continue;
      }
      peer.serializeAttachment({ ...mobile, suppressDisconnect: true });
      peer.close(4002, 'runtime disconnected');
    }
  }
}
