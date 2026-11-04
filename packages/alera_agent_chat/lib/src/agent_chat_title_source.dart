import 'package:alera_agent_chat/src/agent_chat_json.dart';

enum AgentChatTitleSource {
  defaultLabel,
  derived,

  /// AI Assist or the chat's agent named the chat
  /// (`agentChatTitleGenerationV1`).
  generated,
  user;

  String get wire => this == defaultLabel ? 'default' : name;

  static AgentChatTitleSource fromJson(Object? value) => switch (value) {
    'derived' => derived,
    'generated' => generated,
    'user' => user,
    _ => defaultLabel,
  };
}

/// Where a chat's AI title job stands (`agentChatTitleGenerationV1`).
class const AgentChatTitleGeneration({
  /// `idle`, `generating` or `failed`.
  final String status = 'idle',

  /// `auto` for the first-turn title, `regenerate` when someone asked.
  final String? mode,
  final String? errorMessage,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTitleGeneration(
      status: agentChatJsonString(json['status']) ?? 'idle',
      mode: agentChatJsonString(json['mode']),
      errorMessage: agentChatJsonString(json['errorMessage']),
    );
  }

  bool get generating => status == 'generating';
  bool get failed => status == 'failed';
}

AgentChatTitleGeneration? agentChatTitleGenerationFromJson(Object? value) =>
    value is Map ? AgentChatTitleGeneration.fromJson(value) : null;
