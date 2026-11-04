import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// Live adapter support, separate from host support for the corresponding verbs.
class const AgentChatNativeHistoryCapabilities({
  final bool forkAtTurn = false,
  final bool forkAtMessage = false,
  final bool rollbackRemoveTurns = false,
  final bool rollbackBeforeTurn = false,
  final bool rewindFiles = false,
  final bool fileCheckpointing = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatNativeHistoryCapabilities(
      forkAtTurn: agentChatJsonBool(json['forkAtTurn']),
      forkAtMessage: agentChatJsonBool(json['forkAtMessage']),
      rollbackRemoveTurns: agentChatJsonBool(json['rollbackRemoveTurns']),
      rollbackBeforeTurn: agentChatJsonBool(json['rollbackBeforeTurn']),
      rewindFiles: agentChatJsonBool(json['rewindFiles']),
      fileCheckpointing: agentChatJsonBool(json['fileCheckpointing']),
    );
  }
}
