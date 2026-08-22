import 'package:dart_mappable/dart_mappable.dart';

part 'agent_status.mapper.dart';

@MappableEnum()
enum AgentStatusState {
  working('working'),
  waiting('waiting'),
  blocked('blocked'),
  done('done');

  const AgentStatusState(this.key);

  final String key;
}

@MappableEnum()
enum AgentType {
  codex('codex'),
  claude('claude'),
  copilot('copilot'),
  cursor('cursor'),
  agy('agy'),
  opencode('opencode'),
  opencode2('opencode2'),
  pi('pi'),
  amp('amp'),
  grok('grok'),
  fx('fx');

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

/// Value equality matters here: the host snapshot rebuilds these on every
/// presence event, so without it no Riverpod short-circuit can fire and an
/// unchanged snapshot still rebuilds the sidebar.
@MappableClass()
class AgentStatusEntry with AgentStatusEntryMappable {
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
}
