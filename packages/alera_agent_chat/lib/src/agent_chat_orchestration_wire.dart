import 'package:alera_agent_chat/src/agent_chat_error_message.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// Wire names of chat orchestration: tasks a person or an agent hands to an
/// agent chat in any project or host the runtime knows. It is separate from
/// terminal orchestration and from the `agentChat.*` verbs it builds on.
abstract final class AgentChatOrchestrationWire {
  static const String capability = 'chatOrchestrationV1';
  static const String personParentCapability =
      'chatOrchestrationPersonParentV1';
  static const String effortCapability = 'chatOrchestrationEffortV1';
  static const String changedEvent = 'chatOrchestrationChanged';

  static const String capabilities = 'chatOrchestration.capabilities';
  static const String delegate = 'chatOrchestration.delegate';
  static const String send = 'chatOrchestration.send';
  static const String task = 'chatOrchestration.task';
  static const String tasksList = 'chatOrchestration.tasks.list';
  static const String wait = 'chatOrchestration.wait';
  static const String cancel = 'chatOrchestration.cancel';
  static const String interrupt = 'chatOrchestration.interrupt';
  static const String requests = 'chatOrchestration.requests';
  static const String respond = 'chatOrchestration.respond';
  static const String configure = 'chatOrchestration.configure';
  static const String read = 'chatOrchestration.read';
  static const String list = 'chatOrchestration.list';

  /// The longest wait the runtime holds open; callers wait again for more.
  static const int maxWaitSeconds = 50;
}

/// `errorCode` values of `chatOrchestration.*`. The runtime sends snake_case;
/// older builds sent camelCase, so codes are compared as folded tokens.
abstract final class AgentChatOrchestrationErrorCodes {
  static const String taskNotFound = 'task_not_found';
  static const String chatNotFound = 'chat_not_found';
  static const String chatArchived = 'chat_archived';
  static const String notInLineage = 'not_in_lineage';
  static const String modeCeiling = 'mode_ceiling';
  static const String invalidTarget = 'invalid_target';
  static const String hostUnavailable = 'host_unavailable';
  static const String requestConflict = 'request_conflict';
  static const String unsupported = 'unsupported';

  static bool matches(String? code, String expected) =>
      code != null && agentChatWireToken(code) == agentChatWireToken(expected);
}

/// The runtime does not advertise [AgentChatOrchestrationWire.capability].
final class const AgentChatOrchestrationUpdateRequired() implements Exception {
  @override
  String toString() =>
      'This Alera runtime cannot run chat tasks yet. Update it to continue.';
}

/// One sentence both apps show for a failed chat task action. Unknown
/// runtime failures keep the runtime's own message, which is user-facing.
String agentChatOrchestrationErrorMessage(Object error) {
  if (error is AgentChatOrchestrationUpdateRequired ||
      error is AgentChatUpdateRequired ||
      error is AgentChatConnectionException) {
    return error is AgentChatConnectionException
        ? agentChatErrorMessage(error)
        : error.toString();
  }
  if (error is! AgentChatRequestException) {
    return 'The chat task action failed.';
  }
  final code = error.code;
  bool matches(String expected) =>
      AgentChatOrchestrationErrorCodes.matches(code, expected);
  if (matches(AgentChatOrchestrationErrorCodes.taskNotFound)) {
    return 'This task no longer exists on the runtime.';
  }
  if (matches(AgentChatOrchestrationErrorCodes.chatNotFound)) {
    return 'This chat no longer exists on the runtime.';
  }
  if (matches(AgentChatOrchestrationErrorCodes.chatArchived)) {
    return 'This chat is archived. Reopen it to continue.';
  }
  if (matches(AgentChatOrchestrationErrorCodes.requestConflict)) {
    return 'This action was already sent with different details. Try again.';
  }
  if (matches(AgentChatOrchestrationErrorCodes.hostUnavailable)) {
    return error.message.trim().isEmpty
        ? 'The host that owns this chat is not reachable.'
        : error.message;
  }
  return error.message.trim().isEmpty
      ? 'The chat task action failed.'
      : error.message;
}
