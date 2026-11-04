import 'package:alera_agent_chat/src/agent_chat_json.dart';

const String agentChatProviderCommandFallbackDetail = 'Runs in the agent.';

/// A slash command the agent behind a chat advertises, such as Claude's
/// `/compact` or an ACP agent's `/web`. The agent expands it itself when a
/// prompt starts with it, so the composer only inserts the text.
final class const AgentChatProviderCommand({
  required final String name,
  final String? description,
  final String? inputHint,
}) {
  /// A command of the runtime's `session.commands`, or `null` without a
  /// name that can be typed as one token.
  static AgentChatProviderCommand? tryParse(Object? value) {
    final json = agentChatJsonMap(value);
    final typed = agentChatJsonString(json['name'])?.trim() ?? '';
    final name = typed.startsWith('/') ? typed.substring(1) : typed;
    if (name.isEmpty || name.contains(RegExp(r'\s'))) return null;
    String? text(Object? value) => agentChatJsonString(value)?.trim();

    return AgentChatProviderCommand(
      name: name,
      description: text(json['description']),
      inputHint: text(agentChatJsonMap(json['input'])['hint']),
    );
  }

  /// The command as typed, such as `/compact`.
  String get label => '/$name';

  /// What the menu shows beside the name: the description, else the hint of
  /// what to type after it, as T3 Code does.
  String get detail =>
      description ?? inputHint ?? agentChatProviderCommandFallbackDetail;

  /// What picking the command puts in the prompt: the command and a space,
  /// for the person to finish and send, as T3 Code does.
  String get insertion => '/$name ';

  @override
  bool operator ==(Object other) =>
      other is AgentChatProviderCommand &&
      other.name == name &&
      other.description == description &&
      other.inputHint == inputHint;

  @override
  int get hashCode => Object.hash(name, description, inputHint);
}

/// The commands of a session's `commands` list, one per name.
List<AgentChatProviderCommand> agentChatProviderCommandsFromJson(
  Object? value,
) {
  final seen = <String>{};
  return <AgentChatProviderCommand>[
    for (final entry in agentChatJsonList(value))
      if (AgentChatProviderCommand.tryParse(entry) case final command?)
        if (seen.add(command.name.toLowerCase())) command,
  ];
}
