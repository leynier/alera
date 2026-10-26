import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_session.dart';
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
  static const String revisionConflict = 'revisionConflict';
  static const String providerInstanceInUse = 'providerInstanceInUse';
  static const String notAllowed = 'notAllowed';
  static const String nativeOperationUncertain = 'nativeOperationUncertain';
  static const String nativeOperationPending = 'nativeOperationPending';
  static const String nativeOperationRevisionConflict =
      'nativeOperationRevisionConflict';
}

/// One sentence both apps show for a failed chat action. Unknown failures
/// keep the runtime's own message, which is already user-facing.
String agentChatErrorMessage(Object error) => switch (error) {
  AgentChatUpdateRequired() => error.toString(),
  AgentChatCapabilityRequired() => error.toString(),
  AgentChatConnectionException() =>
    'The Alera runtime is not reachable. The action will not repeat '
        'until you try again.',
  AgentChatRequestException(
    code: AgentChatErrorCodes.nativeOperationUncertain,
  ) =>
    'Alera could not confirm how the rewind ended. Choose how to continue '
        'in the notice above the composer. Your draft is kept.',
  AgentChatRequestException(code: AgentChatErrorCodes.nativeOperationPending) =>
    'A rewind is still being resolved. Send is paused and your draft is kept.',
  AgentChatRequestException(
    code: AgentChatErrorCodes.nativeOperationRevisionConflict,
  ) =>
    'The chat changed while the rewind was being resolved. Review the latest '
        'state and choose again.',
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

/// What a failed turn tells the person: one sentence for a failure the
/// provider classified, followed by the provider's own text, which can say
/// more (such as when a limit resets). Unclassified failures keep only the
/// provider's text.
String agentChatTurnFailureMessage(AgentChatTurn turn) {
  final raw = turn.errorMessage?.trim() ?? '';
  final guidance = switch (turn.failureClass) {
    AgentChatFailureClass.usageLimit =>
      "The provider's usage limit was reached. Send the message again once "
          'the limit resets.',
    AgentChatFailureClass.contextWindowFull =>
      "The conversation no longer fits the model's context window. Compact "
          'it or start a new chat.',
    AgentChatFailureClass.auth =>
      'The provider rejected its sign-in. Sign in to the provider again, '
          'then retry.',
    AgentChatFailureClass.previousTurnActive =>
      'The previous turn is still running. Wait for it to finish, then send '
          'again.',
    AgentChatFailureClass.attachmentUnreadable =>
      'An attachment could not be read. Attach it again, then retry.',
    AgentChatFailureClass.unknown => null,
  };
  if (guidance == null) return raw.isEmpty ? 'The turn failed.' : raw;
  return raw.isEmpty ? guidance : '$guidance\n$raw';
}
