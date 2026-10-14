import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';

/// The desktop runtime client as the shared agent chat repository needs it:
/// host errors become package exceptions and the socket's connection events
/// become the package's lifecycle events.
final class RuntimeHostAgentChatTransport implements AgentChatTransport {
  RuntimeHostAgentChatTransport(this._client);

  final RuntimeHostClient _client;

  @override
  Stream<AgentChatTransportEvent> get events => _client.runtimeEvents.map(
    (event) => AgentChatTransportEvent(switch (event.name) {
      aleraRuntimeHostConnectedEvent => AgentChatTransportEvents.connected,
      aleraRuntimeHostDisconnectedEvent =>
        AgentChatTransportEvents.disconnected,
      _ => event.name,
    }, event.payload),
  );

  @override
  Future<bool> supportsCapability(String capability) async {
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          capability,
        );
  }

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final Object? response;
    try {
      response = await _client.runtimeRequest(
        type,
        payload,
        timeout ?? runtimeSnapshotRequestTimeout,
      );
    } on TerminalHostConflictException catch (error) {
      throw AgentChatRequestException(
        message: error.message,
        code: error.code,
        details: error.details,
      );
    } on TerminalHostConnectionClosedException catch (error) {
      throw AgentChatConnectionException(error.toString());
    } on TerminalHostRequestTimeoutException catch (error) {
      throw AgentChatConnectionException(error.toString());
    } on StateError catch (error) {
      throw AgentChatRequestException(message: error.message);
    }
    return agentChatJsonMap(response);
  }
}
