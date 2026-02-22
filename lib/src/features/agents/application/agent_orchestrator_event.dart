sealed class AgentOrchestratorEvent {
  const AgentOrchestratorEvent();
}

class AgentNotificationEvent extends AgentOrchestratorEvent {
  const AgentNotificationEvent({required this.method, required this.payload});

  final String method;
  final Map<String, dynamic> payload;
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
