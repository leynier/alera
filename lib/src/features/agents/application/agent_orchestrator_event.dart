sealed class AgentOrchestratorEvent {
  const AgentOrchestratorEvent();
}

class AgentNotificationEvent extends AgentOrchestratorEvent {
  const AgentNotificationEvent({required this.method, required this.payload});

  final String method;
  final Map<String, dynamic> payload;
}

class AgentApprovalRequestEvent extends AgentOrchestratorEvent {
  const AgentApprovalRequestEvent({
    required this.requestId,
    required this.method,
    required this.description,
    this.threadId,
    this.options = const <AgentApprovalOption>[],
  });

  final Object requestId;
  final String method;
  final String description;
  final String? threadId;
  final List<AgentApprovalOption> options;
}

class AgentApprovalOption {
  const AgentApprovalOption({
    required this.optionId,
    required this.name,
    this.kind,
  });

  final String optionId;
  final String name;
  final String? kind;
}

class AgentToolCallRequestEvent extends AgentOrchestratorEvent {
  const AgentToolCallRequestEvent({
    required this.requestId,
    required this.threadId,
    required this.turnId,
    required this.tool,
    required this.arguments,
  });

  final Object requestId;
  final String threadId;
  final String turnId;
  final String tool;
  final Map<String, dynamic> arguments;
}

class AgentUserInputRequestEvent extends AgentOrchestratorEvent {
  const AgentUserInputRequestEvent({
    required this.requestId,
    required this.threadId,
    required this.turnId,
    required this.itemId,
    required this.questions,
  });

  final Object requestId;
  final String? threadId;
  final String turnId;
  final String itemId;
  final List<Map<String, dynamic>> questions;
}
