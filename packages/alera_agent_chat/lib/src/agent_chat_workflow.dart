import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// Where one member of a workflow is, as the provider reported it. Anything
/// else reads as running: guessing settled would freeze a live row.
enum AgentChatWorkflowAgentState {
  queued,
  running,
  completed,
  failed;

  static AgentChatWorkflowAgentState fromJson(Object? value) =>
      switch (agentChatWireToken(value)) {
        'queued' => queued,
        'completed' => completed,
        'failed' => failed,
        _ => running,
      };
}

final class const AgentChatWorkflowPhase({
  required final int index,
  required final String title,
});

/// One member of a workflow run, identified by its spawn ordinal [index].
final class const AgentChatWorkflowAgent({
  required final int index,
  required final String label,
  required final AgentChatWorkflowAgentState state,

  /// Provider-assigned once it starts; its answers are readable from then.
  final String? agentId,
  final int? phaseIndex,
  final String? phaseTitle,
  final String? model,

  /// Above 1 when the member restarted after an error.
  final int? attempt,
  final int? totalTokens,
  final int? toolCalls,
  final int? durationMs,
  final DateTime? queuedAt,
  final DateTime? startedAt,

  /// Excerpts of what the member was asked and answered.
  final String? prompt,
  final String? result,
});

/// The script and transcripts the provider keeps for a run.
final class const AgentChatWorkflowRunHandles({
  final String? runId,
  final String? transcriptDir,
  final String? scriptPath,
});

/// A provider-native workflow (`normalized.subagent.workflow`): a script
/// that starts sub-agents in phases, with what the provider reported of its
/// plan, members and usage.
final class const AgentChatWorkflow({
  final String? name,
  final AgentChatWorkflowRunHandles? runHandles,
  final List<AgentChatWorkflowPhase> phases = const <AgentChatWorkflowPhase>[],
  final List<AgentChatWorkflowAgent> agents = const <AgentChatWorkflowAgent>[],
  final int? totalTokens,
  final int? toolCalls,
  final int? durationMs,
}) {
  /// `null` unless [value] is an object. Entries that do not parse are
  /// dropped: the shape comes from undocumented provider telemetry.
  static AgentChatWorkflow? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = agentChatJsonMap(value);
    final handles = agentChatJsonMap(json['runHandles']);
    return AgentChatWorkflow(
      name: agentChatJsonString(json['name']),
      runHandles: handles.isEmpty
          ? null
          : AgentChatWorkflowRunHandles(
              runId: agentChatJsonString(handles['runId']),
              transcriptDir: agentChatJsonString(handles['transcriptDir']),
              scriptPath: agentChatJsonString(handles['scriptPath']),
            ),
      phases: <AgentChatWorkflowPhase>[
        for (final entry in agentChatJsonList(json['phases']))
          ?_phase(agentChatJsonMap(entry)),
      ],
      agents: <AgentChatWorkflowAgent>[
        for (final entry in agentChatJsonList(json['agents']))
          ?_agent(agentChatJsonMap(entry)),
      ],
      totalTokens: _count(json['totalTokens']),
      toolCalls: _count(json['toolCalls']),
      durationMs: _count(json['durationMs']),
    );
  }

  String? get scriptPath => runHandles?.scriptPath;
}

int? _count(Object? value) {
  final count = value is num && value.isFinite && value == value.truncate()
      ? value.toInt()
      : null;
  return count != null && count >= 0 ? count : null;
}

DateTime? _instant(Object? value) {
  final millis = _count(value);
  if (millis == null || millis > 8640000000000000) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

AgentChatWorkflowPhase? _phase(AgentChatJson json) {
  final index = _count(json['index']);
  final title = agentChatJsonString(json['title'])?.trim();
  return index == null || title == null
      ? null
      : AgentChatWorkflowPhase(index: index, title: title);
}

AgentChatWorkflowAgent? _agent(AgentChatJson json) {
  final index = _count(json['index']);
  final label = agentChatJsonString(json['label'])?.trim();
  if (index == null || label == null) return null;
  return AgentChatWorkflowAgent(
    index: index,
    label: label,
    state: AgentChatWorkflowAgentState.fromJson(json['state']),
    agentId: agentChatJsonString(json['agentId']),
    phaseIndex: _count(json['phaseIndex']),
    phaseTitle: agentChatJsonString(json['phaseTitle'])?.trim(),
    model: agentChatJsonString(json['model']),
    attempt: _count(json['attempt']),
    totalTokens: _count(json['totalTokens']),
    toolCalls: _count(json['toolCalls']),
    durationMs: _count(json['durationMs']),
    queuedAt: _instant(json['queuedAt']),
    startedAt: _instant(json['startedAt']),
    prompt: _text(json['prompt']),
    result: _text(json['result']),
  );
}

/// `agentChat.workflowScript`: the script a workflow runs.
final class const AgentChatWorkflowScript({
  required final String scriptPath,
  required final String contents,

  /// The script is longer than the 256 KiB the runtime reads.
  final bool truncated = false,
}) {
  factory AgentChatWorkflowScript.fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatWorkflowScript(
      scriptPath: agentChatJsonText(json['scriptPath']),
      contents: agentChatJsonText(json['contents']),
      truncated: agentChatJsonBool(json['truncated']),
    );
  }
}

/// `agentChat.workflowAgent`: the text of each turn one member answered.
List<String> agentChatWorkflowAgentAnswers(Object? value) => <String>[
  for (final answer in agentChatJsonList(agentChatJsonMap(value)['answers']))
    if (answer is String && answer.trim().isNotEmpty) answer,
];
