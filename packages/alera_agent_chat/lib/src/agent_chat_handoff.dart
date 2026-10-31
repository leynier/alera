import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';

enum AgentChatHandoffStatus {
  pending,
  completed,
  failed;

  static AgentChatHandoffStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatHandoffStatus.values,
    AgentChatHandoffStatus.pending,
  );
}

/// One side of a context handoff: the provider and model a session ran on.
class const AgentChatHandoffEndpoint({
  required final String provider,
  final String? providerInstanceId,
  final String? model,
}) {
  static AgentChatHandoffEndpoint? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = agentChatJsonMap(value);
    final provider = agentChatJsonString(json['provider']);
    if (provider == null) return null;
    return AgentChatHandoffEndpoint(
      provider: provider,
      providerInstanceId: agentChatJsonString(json['providerInstanceId']),
      model: agentChatJsonString(json['model']),
    );
  }
}

/// The transcript of earlier sessions reaching a fresh provider session with
/// a turn's prompt. The runtime records it as a `notice` whose `normalized`
/// carries `handoff`; [from] is null when no earlier turn names a source.
class const AgentChatHandoff({
  final AgentChatHandoffEndpoint? from,
  required final AgentChatHandoffEndpoint to,
  required final AgentChatHandoffStatus status,
}) {
  static AgentChatHandoff? fromItem(AgentChatItem item) {
    if (item.type != AgentChatItemType.notice) return null;
    final payload = item.normalized['handoff'];
    if (payload is! Map) return null;
    final json = agentChatJsonMap(payload);
    final to = AgentChatHandoffEndpoint.fromJson(json['to']);
    if (to == null) return null;
    return AgentChatHandoff(
      from: AgentChatHandoffEndpoint.fromJson(json['from']),
      to: to,
      status: item.isFailed
          ? AgentChatHandoffStatus.failed
          : AgentChatHandoffStatus.fromJson(json['status']),
    );
  }

  bool get failed => status == AgentChatHandoffStatus.failed;
}
