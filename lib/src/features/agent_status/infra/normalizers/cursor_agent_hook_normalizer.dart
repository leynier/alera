part of '../agent_hook_event_normalizer.dart';

AgentStatusState? _normalizeCursorState(
  String eventName,
  AgentStatusEntry? previous,
) {
  return switch (eventName) {
    'beforeSubmitPrompt' ||
    'sessionStart' ||
    'preToolUse' ||
    'postToolUse' ||
    'postToolUseFailure' => AgentStatusState.working,
    'beforeShellExecution' || 'beforeMCPExecution' => AgentStatusState.waiting,
    'afterAgentResponse' =>
      previous?.agentType == AgentType.cursor &&
              previous?.state == AgentStatusState.done
          ? AgentStatusState.done
          : AgentStatusState.working,
    'stop' || 'sessionEnd' => AgentStatusState.done,
    _ => null,
  };
}

bool _isCursorNewTurn(String eventName) {
  return eventName == 'beforeSubmitPrompt' || eventName == 'sessionStart';
}

_ToolSnapshot _extractCursorToolSnapshot(
  AgentHookEvent event,
  String eventName,
) {
  final payload = event.payload;
  return switch (eventName) {
    'preToolUse' ||
    'postToolUse' ||
    'postToolUseFailure' => _cursorToolUseSnapshot(payload, eventName),
    'beforeShellExecution' => _ToolSnapshot(
      toolName: 'Shell',
      toolInput: _readFirstString(payload, const <String>['command']),
      hasToolUpdate: true,
      hasToolInput: payload.containsKey('command'),
    ),
    'beforeMCPExecution' => _cursorMcpSnapshot(payload),
    'afterAgentResponse' => _ToolSnapshot(
      lastAssistantMessage: _readCursorMultiline(payload, const <String>[
        'text',
      ]),
    ),
    _ => const _ToolSnapshot(),
  };
}

_ToolSnapshot _cursorToolUseSnapshot(
  Map<String, Object?> payload,
  String eventName,
) {
  final toolName = _readFirstString(payload, const <String>[
    'tool_name',
    'toolName',
    'name',
    'tool',
  ]);
  final input = _cursorFirstPresent(payload, const <String>[
    'tool_input',
    'toolInput',
    'toolArgs',
    'input',
    'arguments',
  ]);
  final lastAssistantMessage = switch (eventName) {
    'postToolUse' =>
      _extractToolResponseText(payload['tool_output']) ??
          _extractToolResponseText(payload['toolOutput']) ??
          _extractToolResponseText(payload['output']),
    'postToolUseFailure' =>
      _extractToolResponseText(payload['tool_output']) ??
          _extractToolResponseText(payload['toolOutput']) ??
          _extractToolResponseText(payload['output']) ??
          _readCursorMultiline(payload, const <String>[
            'error_message',
            'errorMessage',
            'error',
          ]),
    _ => null,
  };
  return _ToolSnapshot(
    toolName: toolName,
    toolInput: input == null ? null : _deriveToolInputPreview(toolName, input),
    lastAssistantMessage: lastAssistantMessage,
    hasToolUpdate: true,
    hasToolInput: input != null,
  );
}

_ToolSnapshot _cursorMcpSnapshot(Map<String, Object?> payload) {
  final toolName =
      _readFirstString(payload, const <String>['tool_name', 'toolName']) ??
      'MCP';
  final input =
      _cursorFirstPresent(payload, const <String>[
        'tool_input',
        'toolInput',
        'input',
        'arguments',
      ]) ??
      _cursorFirstPresent(payload, const <String>['command', 'url']);
  return _ToolSnapshot(
    toolName: toolName,
    toolInput: input == null ? null : _deriveToolInputPreview(toolName, input),
    hasToolUpdate: true,
    hasToolInput: input != null,
  );
}

Object? _cursorFirstPresent(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    if (payload.containsKey(key)) {
      return payload[key];
    }
  }
  return null;
}

String? _readCursorMultiline(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return _normalizeMultiline(value, 8000);
    }
  }
  return null;
}

bool _isCursorInterrupted(AgentHookEvent event) {
  if (_isGenericInterrupted(event)) {
    return true;
  }
  final status = _readFirstString(event.payload, const <String>['status']);
  return status != null && status != 'completed';
}
