import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';

final class AgentChatContractTransport implements AgentChatTransport {
  AgentChatContractTransport({Set<String>? capabilities})
    : capabilities = capabilities ?? <String>{AgentChatWire.capability};

  final Set<String> capabilities;
  final requests = <(String, Map<String, Object?>)>[];
  final responses = <String, Map<String, Object?>>{};
  final controller = StreamController<AgentChatTransportEvent>.broadcast();

  @override
  Stream<AgentChatTransportEvent> get events => controller.stream;

  @override
  Future<bool> supportsCapability(String capability) async =>
      capabilities.contains(capability);

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload));
    return responses[type] ?? <String, Object?>{};
  }
}

Map<String, Object?> agentChatContractSnapshot() => <String, Object?>{
  'chatId': 'c',
  'workspaceId': 'w',
  'cursor': 3,
  'provider': 'codex',
  'providerInstanceId': 'codex',
};
