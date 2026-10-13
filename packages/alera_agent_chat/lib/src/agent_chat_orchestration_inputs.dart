import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_target.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_task.dart';

/// The agent a new child chat starts with, from the runtime's catalog.
class const AgentChatTaskAgent({
  required final String providerInstanceId,
  final String? model,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'providerInstanceId': providerInstanceId,
    'model': ?model,
  };
}

/// `chatOrchestration.delegate`. A person's delegation never waits on the
/// runtime: it is always `async`, and the task list follows its progress.
class const AgentChatDelegateInput({
  required final String requestId,
  required final String task,
  required final AgentChatTaskTarget target,
  final String? title,
  final String? role,
  final AgentChatTaskNotify? notify,
  final AgentChatTaskAgent? agent,
  final AgentChatRuntimeMode? runtimeMode,
  final AgentChatInteractionMode? interactionMode,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'requestId': requestId,
    'task': task,
    'mode': 'async',
    'target': target.toJson(),
    'title': ?title,
    'role': ?role,
    'notify': ?notify?.wire,
    'agent': ?agent?.toJson(),
    'runtimeMode': ?runtimeMode?.wire,
    'interactionMode': ?interactionMode?.wire,
  };
}

/// What `delegate` created: always a task, plus the chat and workspace when
/// they exist yet (a new workspace may still be preparing).
class const AgentChatDelegateResult({
  required final String taskId,
  required final AgentChatTaskStatus status,
  final String? chatId,
  final String? workspaceId,
  final AgentChatTask? task,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final task = json['task'] is Map
        ? AgentChatTask.fromJson(json['task'])
        : null;
    final taskId = agentChatJsonString(json['taskId']) ?? task?.id;
    if (taskId == null) {
      throw const FormatException('Delegation result has no taskId.');
    }
    return AgentChatDelegateResult(
      taskId: taskId,
      status: json['status'] == null
          ? task?.status ?? AgentChatTaskStatus.preparing
          : AgentChatTaskStatus.fromJson(json['status']),
      chatId: agentChatJsonString(json['chatId']) ?? task?.childChatId,
      workspaceId:
          agentChatJsonString(json['workspaceId']) ?? task?.workspaceId,
      task: task,
    );
  }
}

/// How `chatOrchestration.send` delivers into the target chat: start or
/// queue behind its turn (`auto`), or always wait for the turn end.
enum AgentChatTaskMessageDelivery(final String wire) {
  auto('auto'),
  queue('queue'),
}

/// `chatOrchestration.send`. With [expectReply] the runtime tracks the reply
/// as a message task, so it shows up beside delegations.
class const AgentChatTaskMessageInput({
  required final String requestId,
  required final String chatId,
  required final String message,
  final AgentChatTaskMessageDelivery delivery =
      AgentChatTaskMessageDelivery.auto,
  final bool expectReply = false,
}) {
  AgentChatJson toJson() => <String, Object?>{
    'requestId': requestId,
    'chatId': chatId,
    'message': message,
    'delivery': delivery.wire,
    'expectReply': expectReply,
  };
}

class const AgentChatTaskMessageResult({
  required final String chatId,
  final AgentChatSendDelivery delivery = AgentChatSendDelivery.started,
  final String? taskId,
}) {
  factory fromJson(Object? value, {required String chatId}) {
    final json = agentChatJsonMap(value);
    return AgentChatTaskMessageResult(
      chatId: agentChatJsonString(json['chatId']) ?? chatId,
      delivery: AgentChatSendDelivery.fromJson(json['delivery']),
      taskId: agentChatJsonString(json['taskId']),
    );
  }
}
