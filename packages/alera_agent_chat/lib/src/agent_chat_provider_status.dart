import 'package:alera_agent_chat/src/agent_chat_json.dart';

enum AgentChatProviderAuthStatus {
  signedIn,
  signedOut,
  unknown;

  static AgentChatProviderAuthStatus fromJson(Object? value) =>
      agentChatWireEnum(value, values, unknown);
}

class const AgentChatProviderAuth({
  final AgentChatProviderAuthStatus status =
      AgentChatProviderAuthStatus.unknown,
  final String? label,
  final DateTime? checkedAt,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatProviderAuth(
      status: AgentChatProviderAuthStatus.fromJson(json['status']),
      label: agentChatJsonString(json['label']),
      checkedAt: agentChatJsonDate(json['checkedAt']),
    );
  }

  bool get verified => checkedAt != null && status != .unknown;
}

/// Host-verified commands to run in a command terminal on that host.
class const AgentChatProviderSetupCommand({
  required final String action,
  required final String label,
  required final String command,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatProviderSetupCommand(
      action: agentChatJsonText(json['action']),
      label: agentChatJsonText(json['label']),
      command: agentChatJsonText(json['command']),
    );
  }
}

List<AgentChatProviderSetupCommand> agentChatProviderSetupFromJson(
  Object? value,
) => <AgentChatProviderSetupCommand>[
  for (final command in agentChatJsonList(value))
    if (command is Map) AgentChatProviderSetupCommand.fromJson(command),
];
