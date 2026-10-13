import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// `errorCode` values the runtime returns for `agentChat.*`.
abstract final class AgentChatErrorCodes {
  static const String requestConflict = 'request_conflict';
  static const String requestResolved = 'request_resolved';
  static const String unsupported = 'unsupported';
  static const String turnActive = 'turnActive';
  static const String chatNotFound = 'chatNotFound';
  static const String chatArchived = 'chatArchived';
  static const String providerUnavailable = 'providerUnavailable';
}

/// One sentence both apps show for a failed chat action. Unknown failures
/// keep the runtime's own message, which is already user-facing.
String agentChatErrorMessage(Object error) => switch (error) {
  AgentChatUpdateRequired() => error.toString(),
  AgentChatConnectionException() =>
    'The Alera runtime is not reachable. The action will not repeat '
        'until you try again.',
  AgentChatRequestException(code: AgentChatErrorCodes.requestResolved) =>
    'This request was already answered.',
  AgentChatRequestException(code: AgentChatErrorCodes.turnActive) =>
    'Wait for the current turn, requests and queued messages to finish '
        'first.',
  AgentChatRequestException(code: AgentChatErrorCodes.chatNotFound) =>
    'This chat no longer exists on the runtime.',
  AgentChatRequestException(code: AgentChatErrorCodes.chatArchived) =>
    'This chat is archived. Reopen it to continue.',
  AgentChatRequestException(code: AgentChatErrorCodes.providerUnavailable) =>
    error.message.trim().isEmpty
        ? 'The agent provider is not available on this runtime.'
        : error.message,
  AgentChatRequestException(code: AgentChatErrorCodes.unsupported) =>
    error.message.trim().isEmpty
        ? 'The agent provider does not support this action.'
        : error.message,
  AgentChatRequestException(:final message) when message.trim().isNotEmpty =>
    message,
  _ => 'The agent chat action failed.',
};
