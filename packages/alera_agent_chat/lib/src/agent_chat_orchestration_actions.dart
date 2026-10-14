import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_query.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_repository.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_task.dart';

/// What a person does to chat tasks, on the desktop and on a phone alike.
/// Each press is a new request; the runtime's receipts make a retried press
/// safe. Nothing here selects a workspace or a tab.
final class AgentChatTaskActions {
  AgentChatTaskActions(this._repository, this._newId);

  final AgentChatOrchestrationRepository _repository;
  final String Function() _newId;

  /// The delegation's request id comes from its form, so a retry of an
  /// unchanged form replays the receipt.
  Future<AgentChatDelegateResult> delegate(AgentChatDelegateInput input) =>
      _repository.delegate(input);

  Future<AgentChatTask> cancel(String taskId) =>
      _repository.cancel(taskId, requestId: _newId());

  /// Whether reading [task] should take its settled result off Attention:
  /// only for tasks a person owns, since a parent chat still has to read its
  /// children's results.
  static bool acknowledges(AgentChatTask task) =>
      task.ownedByPerson &&
      task.status.settled &&
      task.delivery != AgentChatTaskDelivery.acknowledged;

  Future<void> acknowledge(AgentChatTask task) async {
    if (!acknowledges(task)) return;
    await _repository.task(task.id, acknowledge: true);
  }

  Future<void> approve(
    AgentChatTaskRequest request,
    AgentChatApprovalDecision decision,
  ) => _repository.respond(
    chatId: request.chatId,
    requestId: _newId(),
    runtimeRequestId: request.request.id,
    response: AgentChatApprovalResponse(decision),
  );

  /// Waits up to the runtime's maximum for the task to settle.
  Future<AgentChatTaskWaitResult> waitFor(String taskId) =>
      _repository.wait(<String>[taskId]);

  /// A new turn in the task's child chat whose reply is tracked as a task.
  Future<AgentChatTaskMessageResult> followUp(String chatId, String message) =>
      _repository.send(
        AgentChatTaskMessageInput(
          requestId: _newId(),
          chatId: chatId,
          message: message.trim(),
          expectReply: true,
        ),
      );
}
