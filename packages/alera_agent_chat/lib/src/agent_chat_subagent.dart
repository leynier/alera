import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// Where a provider-native sub-agent is.
enum AgentChatSubagentStatus {
  running,
  completed,
  failed,
  stopped;

  static AgentChatSubagentStatus fromJson(Object? value) =>
      switch (agentChatWireToken(value)) {
        'completed' => completed,
        'failed' => failed,
        'stopped' => stopped,
        _ => running,
      };

  bool get settled => this != running;

  String get label => switch (this) {
    running => 'Running',
    completed => 'Completed',
    failed => 'Failed',
    stopped => 'Stopped',
  };
}

/// What the runtime knows about the sub-agent a tool call started
/// (`normalized.subagent`): Claude's Task tool, Codex's collab agents.
class const AgentChatSubagent({
  required final AgentChatSubagentStatus status,
  final String? taskId,
  final String? description,
  final String? summary,
  final String? taskType,
}) {
  static AgentChatSubagent? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = agentChatJsonMap(value);
    return AgentChatSubagent(
      status: AgentChatSubagentStatus.fromJson(json['status']),
      taskId: agentChatJsonString(json['taskId']),
      description: agentChatJsonString(json['description']),
      summary: agentChatJsonString(json['summary']),
      taskType: agentChatJsonString(json['taskType']),
    );
  }
}

extension AgentChatSubagentItem on AgentChatItem {
  AgentChatSubagent? get subagent =>
      AgentChatSubagent.fromJson(normalized['subagent']);

  /// Whether this item started a sub-agent: the runtime saw sub-agent work
  /// under it, or it is a call that only exists to start one.
  bool get startsSubagent {
    if (normalized['subagent'] is Map) return true;
    if (type == AgentChatItemType.collabAgentToolCall) return true;
    final tool = agentChatWireToken(toolName ?? title);
    // Claude Code names its sub-agent tool Task, newer releases Agent.
    return (type == AgentChatItemType.dynamicToolCall ||
            type == AgentChatItemType.mcpToolCall) &&
        (tool == 'task' || tool == 'agent');
  }

  /// "Explore the parser", from the runtime's task or the call's input.
  String get subagentLabel {
    final input = agentChatJsonMap(this.input);
    final candidates = <String?>[
      subagent?.description,
      agentChatJsonString(input['description']),
      agentChatJsonString(input['subagent_type']),
      agentId,
    ];
    for (final candidate in candidates) {
      final text = candidate?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return 'Sub-agent';
  }

  /// The sub-agent's state, falling back to the call's own status before
  /// the provider reports the task.
  AgentChatSubagentStatus get subagentStatus =>
      subagent?.status ??
      (isInProgress
          ? AgentChatSubagentStatus.running
          : isFailed
          ? AgentChatSubagentStatus.failed
          : AgentChatSubagentStatus.completed);
}
