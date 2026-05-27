part of '../agent_hook_event_normalizer.dart';

AgentStatusState? _normalizeCodexState(String eventName, String? toolName) {
  if (eventName == 'PreToolUse' && _isHumanInputTool(toolName)) {
    return AgentStatusState.waiting;
  }
  return switch (eventName) {
    'SessionStart' ||
    'UserPromptSubmit' ||
    'PreToolUse' ||
    'PostToolUse' => AgentStatusState.working,
    'PermissionRequest' => AgentStatusState.waiting,
    'Stop' => AgentStatusState.done,
    _ => null,
  };
}

bool _isCodexNewTurn(String eventName) {
  return eventName == 'SessionStart' || eventName == 'UserPromptSubmit';
}

_NestedToolCall _readCodexToolCall(Map<String, Object?> payload) {
  final toolCall = payload['toolCall'] ?? payload['tool_call'];
  if (toolCall is Map) {
    final record = Map<String, Object?>.from(toolCall);
    return _NestedToolCall(
      toolName: _readFirstString(record, const <String>[
        'name',
        'toolName',
        'tool_name',
      ]),
      toolInputSource:
          _parseJsonObjectString(record['args']) ??
          record['args'] ??
          _parseJsonObjectString(record['arguments']) ??
          record['arguments'],
    );
  }

  final toolCalls = payload['toolCalls'] ?? payload['tool_calls'];
  if (toolCalls is List && toolCalls.isNotEmpty && toolCalls.first is Map) {
    final record = Map<String, Object?>.from(toolCalls.first as Map);
    return _NestedToolCall(
      toolName: _readFirstString(record, const <String>[
        'name',
        'toolName',
        'tool_name',
      ]),
      toolInputSource:
          _parseJsonObjectString(record['args']) ??
          record['args'] ??
          _parseJsonObjectString(record['arguments']) ??
          record['arguments'],
    );
  }

  return const _NestedToolCall();
}
