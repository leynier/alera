import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';

/// One paired runtime connection as the shared agent chat repository sees it.
///
/// Scoped to a single connection on purpose: the host connection controller
/// replaces the client on every reconnect and every chat provider rebuilds
/// with it, which is what reloads the snapshot. A connection that ends is
/// reported as [AgentChatTransportEvents.disconnected] so the chat can show
/// its last copy as stale in the meantime.
final class MobileAgentChatTransport implements AgentChatTransport {
  MobileAgentChatTransport(this._client);

  final MobileAgentChatClient _client;

  @override
  Future<bool> supportsCapability(String capability) =>
      Future<bool>.value(_client.runtimeCapabilities.contains(capability));

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    try {
      return await _client.requestMap(type, payload, timeout);
    } on RuntimeRequestError catch (error) {
      throw AgentChatRequestException(message: error.message, code: error.code);
    } on TimeoutException {
      throw const AgentChatConnectionException(
        'The host did not answer in time.',
      );
    } on Object catch (error) {
      // A closed or replaced connection fails every pending request; the
      // mutation may still have reached the runtime, so the caller retries
      // with the same request id once the connection is back.
      if (error is StateError || isHostReachabilityFailure(error)) {
        throw AgentChatConnectionException(error.toString());
      }
      rethrow;
    }
  }

  @override
  Stream<AgentChatTransportEvent> get events =>
      Stream<AgentChatTransportEvent>.multi((controller) {
        final subscription = _client.events.listen(
          (event) => controller.add(
            AgentChatTransportEvent(event.name, event.payload),
          ),
          onError: controller.addError,
          onDone: () {
            controller
              ..add(
                const AgentChatTransportEvent(
                  AgentChatTransportEvents.disconnected,
                  <String, Object?>{},
                ),
              )
              ..close();
          },
        );
        controller.onCancel = subscription.cancel;
      });
}
