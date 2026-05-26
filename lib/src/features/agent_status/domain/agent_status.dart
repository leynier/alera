enum AgentStatusState {
  working('working'),
  waiting('waiting'),
  blocked('blocked'),
  done('done');

  const AgentStatusState(this.key);

  final String key;
}

enum AgentType {
  codex('codex'),
  claude('claude'),
  copilot('copilot'),
  agy('agy'),
  opencode('opencode'),
  pi('pi'),
  amp('amp');

  const AgentType(this.key);

  final String key;
}

class AgentHookEvent {
  const AgentHookEvent({
    required this.terminalSessionId,
    required this.workspaceId,
    required this.tabId,
    required this.agentType,
    required this.payload,
    this.hookEventName,
    this.version,
  });

  final String terminalSessionId;
  final String workspaceId;
  final String tabId;
  final AgentType agentType;
  final Map<String, Object?> payload;
  final String? hookEventName;
  final String? version;
}

class AgentStatusEntry {
  const AgentStatusEntry({
    required this.terminalSessionId,
    required this.workspaceId,
    required this.tabId,
    required this.agentType,
    required this.state,
    required this.prompt,
    required this.updatedAt,
    required this.stateStartedAt,
    this.toolName,
    this.toolInput,
    this.lastAssistantMessage,
    this.interrupted,
  });

  final String terminalSessionId;
  final String workspaceId;
  final String tabId;
  final AgentType agentType;
  final AgentStatusState state;
  final String prompt;
  final DateTime updatedAt;
  final DateTime stateStartedAt;
  final String? toolName;
  final String? toolInput;
  final String? lastAssistantMessage;
  final bool? interrupted;

  AgentStatusEntry copyWith({
    String? terminalSessionId,
    String? workspaceId,
    String? tabId,
    AgentType? agentType,
    AgentStatusState? state,
    String? prompt,
    DateTime? updatedAt,
    DateTime? stateStartedAt,
    Object? toolName = _sentinel,
    Object? toolInput = _sentinel,
    Object? lastAssistantMessage = _sentinel,
    Object? interrupted = _sentinel,
  }) {
    return AgentStatusEntry(
      terminalSessionId: terminalSessionId ?? this.terminalSessionId,
      workspaceId: workspaceId ?? this.workspaceId,
      tabId: tabId ?? this.tabId,
      agentType: agentType ?? this.agentType,
      state: state ?? this.state,
      prompt: prompt ?? this.prompt,
      updatedAt: updatedAt ?? this.updatedAt,
      stateStartedAt: stateStartedAt ?? this.stateStartedAt,
      toolName: toolName == _sentinel ? this.toolName : toolName as String?,
      toolInput: toolInput == _sentinel ? this.toolInput : toolInput as String?,
      lastAssistantMessage: lastAssistantMessage == _sentinel
          ? this.lastAssistantMessage
          : lastAssistantMessage as String?,
      interrupted: interrupted == _sentinel
          ? this.interrupted
          : interrupted as bool?,
    );
  }
}

const Object _sentinel = Object();
