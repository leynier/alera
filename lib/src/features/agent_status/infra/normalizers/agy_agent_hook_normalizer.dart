part of '../agent_hook_event_normalizer.dart';

AgentStatusState? _normalizeAgyState(
  String eventName,
  String? toolName,
  Map<String, Object?> payload,
) {
  // Alera never installs `PreToolUse`: Antigravity requires a `decision` there,
  // and an observational hook has no value to return that leaves the user's
  // permission policy alone. These branches only run for a hook the user wrote.
  if (eventName == 'PreToolUse' && _isAgyFeedbackTool(toolName)) {
    return AgentStatusState.waiting;
  }
  if (eventName == 'Stop' && _agyStopStillBusy(payload)) {
    return AgentStatusState.working;
  }
  return switch (eventName) {
    'PreInvocation' ||
    'PostInvocation' ||
    'PreToolUse' ||
    'PostToolUse' => AgentStatusState.working,
    'Stop' => AgentStatusState.done,
    _ => null,
  };
}

bool _agyStopStillBusy(Map<String, Object?> payload) {
  return payload['fullyIdle'] == false || payload['fully_idle'] == false;
}

bool _isAgyNewTurn(String eventName) {
  return eventName == 'PreInvocation';
}

String? _agyPromptForEvent(AgentHookEvent event) {
  return _readLastUserPromptFromTranscript(
    event.payload['transcriptPath'] ?? event.payload['transcript_path'],
  );
}

_NestedToolCall _readAgyToolCall(Map<String, Object?> payload) {
  final toolCall = payload['toolCall'];
  if (toolCall is! Map) {
    return const _NestedToolCall();
  }
  final record = Map<String, Object?>.from(toolCall);
  return _NestedToolCall(
    toolName: _readFirstString(record, const <String>[
      'name',
      'toolName',
      'tool_name',
    ]),
    toolInputSource: record['args'],
  );
}

bool _isAgyFeedbackTool(String? toolName) {
  return _isHumanInputTool(toolName);
}
