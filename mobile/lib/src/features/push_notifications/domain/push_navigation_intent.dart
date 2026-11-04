enum PushEventKind {
  attention,
  done,
  terminalExit,
  automation,
  agentChat,
  chatTask,

  /// An agent replied to a question asked from an inbox.
  inboxReply,

  /// A run gate (plan approval, stage gate, stall or decision) is waiting.
  runGate,
  unknown;

  static PushEventKind parse(String? value) {
    return switch (value) {
      'automation' => automation,
      'agentChat' || 'agent_chat_request' => agentChat,
      'chatTask' ||
      'chat_task_attention' ||
      'chat_task_needs_input' => chatTask,
      'inboxReply' || 'inbox_reply' => inboxReply,
      'decisionGate' ||
      'decision_gate' ||
      'gate' ||
      'runGate' ||
      'orchestration.gate.created' ||
      'planApproval' => runGate,
      'waiting' || 'blocked' || 'attention' => attention,
      'done' => done,
      'terminalExit' || 'terminal_exit' => terminalExit,
      _ => unknown,
    };
  }
}

class const PushNavigationIntent({
  required final String runtimeId,
  required final PushEventKind eventKind,
  final String? accountId,
  final String? workspaceId,
  final String? tabId,
  final String? automationId,
  final String? runId,
  final String? threadId,
  final String? gateId,
  final String? gateKind,
  final String? chatId,
  final String? taskId,
}) {
  /// A gate of a run opens the run; a gate on a task outside any run still
  /// goes to the agent's terminal.
  bool get opensRun => eventKind == PushEventKind.runGate && runId != null;

  bool get shouldOpenTerminal =>
      eventKind != PushEventKind.terminalExit &&
      eventKind != PushEventKind.automation &&
      eventKind != PushEventKind.inboxReply &&
      eventKind != PushEventKind.agentChat &&
      eventKind != PushEventKind.chatTask &&
      !opensRun &&
      tabId != null;

  bool get shouldOpenAgentChat =>
      eventKind == PushEventKind.agentChat && chatId != null;

  factory fromData(Map<String, Object?> data) {
    final runtimeId = _nonEmpty(data['runtimeId']);
    if (runtimeId == null) {
      throw const FormatException('Push payload is missing runtime ID');
    }
    return PushNavigationIntent(
      accountId: _nonEmpty(data['accountId']),
      runtimeId: runtimeId,
      workspaceId: _nonEmpty(data['workspaceId']),
      tabId: _nonEmpty(data['tabId']),
      eventKind: _eventKind(data),
      automationId: _nonEmpty(data['automationId']),
      runId: _nonEmpty(data['runId']),
      threadId: _nonEmpty(data['threadId']),
      gateId: _nonEmpty(data['gateId']),
      gateKind: _nonEmpty(data['gateKind']),
      chatId: _nonEmpty(data['chatId']),
      taskId: _nonEmpty(data['taskId']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (accountId != null) 'accountId': accountId,
      'runtimeId': runtimeId,
      if (workspaceId != null) 'workspaceId': workspaceId,
      if (tabId != null) 'tabId': tabId,
      if (automationId != null) 'automationId': automationId,
      if (runId != null) 'runId': runId,
      if (threadId != null) 'threadId': threadId,
      if (gateId != null) 'gateId': gateId,
      if (gateKind != null) 'gateKind': gateKind,
      if (chatId != null) 'chatId': chatId,
      if (taskId != null) 'taskId': taskId,
      'eventType': eventKind.name,
    };
  }
}

PushEventKind _eventKind(Map<String, Object?> data) {
  for (final key in <String>['kind', 'eventType', 'category']) {
    final kind = PushEventKind.parse(_nonEmpty(data[key]));
    if (kind != PushEventKind.unknown) return kind;
  }
  return PushEventKind.unknown;
}

String? _nonEmpty(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
