import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_workflow.dart';
import 'package:alera_agent_chat/src/agent_chat_workflow_groups.dart';

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
  final String? model,
  final String? reasoningEffort,

  /// When the sub-agent last started running, and when it settled.
  final DateTime? startedAt,
  final DateTime? completedAt,

  /// Set when the sub-agent is a workflow (`agentChatWorkflowsV1`).
  final AgentChatWorkflow? workflow,
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
      model: agentChatJsonString(json['model']),
      reasoningEffort: agentChatJsonString(json['reasoningEffort']),
      startedAt: agentChatJsonDate(json['startedAt']),
      completedAt: agentChatJsonDate(json['completedAt']),
      workflow: AgentChatWorkflow.fromJson(json['workflow']),
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

  /// The workflow this call started, grouped by phase; `null` for any
  /// other sub-agent.
  AgentChatWorkflowGroup? get workflowGroup {
    final workflow = subagent?.workflow;
    return workflow == null
        ? null
        : AgentChatWorkflowGroup.build(workflow, subagentStatus);
  }

  /// "Explore the parser", from the runtime's task or the call's input. A
  /// workflow goes by its script's name.
  String get subagentLabel {
    final input = agentChatJsonMap(this.input);
    final candidates = <String?>[
      subagent?.workflow?.name,
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

  /// The model the sub-agent runs on: what the provider reported, else what
  /// the call asked for (Claude's Task tool takes a `model`).
  String? get subagentModel =>
      subagent?.model ?? agentChatJsonString(agentChatJsonMap(input)['model']);

  String? get subagentReasoningEffort =>
      subagent?.reasoningEffort ??
      agentChatJsonString(agentChatJsonMap(input)['reasoningEffort']);

  /// What the call asked the sub-agent to do.
  String? get subagentPrompt =>
      agentChatJsonString(agentChatJsonMap(input)['prompt']) ??
      agentChatJsonString(normalized['prompt']);

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
