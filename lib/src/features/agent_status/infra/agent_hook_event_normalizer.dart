import 'dart:convert';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';

class NormalizedAgentStatus {
  const NormalizedAgentStatus({
    required this.state,
    required this.prompt,
    this.toolName,
    this.toolInput,
    this.lastAssistantMessage,
    this.interrupted,
  });

  final AgentStatusState state;
  final String prompt;
  final String? toolName;
  final String? toolInput;
  final String? lastAssistantMessage;
  final bool? interrupted;
}

NormalizedAgentStatus? normalizeAgentHookEvent(
  AgentHookEvent event, {
  AgentStatusEntry? previous,
}) {
  final eventName = _hookEventName(event);
  if (eventName == null) {
    return null;
  }
  final state = switch (event.agentType) {
    AgentType.codex => _normalizeCodexState(eventName),
    AgentType.claude => _normalizeClaudeState(eventName),
  };
  if (state == null) {
    return null;
  }

  final isNewTurn = eventName == 'UserPromptSubmit';
  final prompt = _extractPrompt(event.payload);
  final toolSnapshot = _extractToolSnapshot(event);
  return NormalizedAgentStatus(
    state: state,
    prompt: prompt.isNotEmpty
        ? prompt
        : (isNewTurn ? '' : previous?.prompt ?? ''),
    toolName: isNewTurn ? null : toolSnapshot.toolName ?? previous?.toolName,
    toolInput: isNewTurn
        ? null
        : toolSnapshot.toolInput ??
              (toolSnapshot.hasToolUpdate ? null : previous?.toolInput),
    lastAssistantMessage:
        toolSnapshot.lastAssistantMessage ?? previous?.lastAssistantMessage,
    interrupted: state == AgentStatusState.done && _isInterrupted(event)
        ? true
        : null,
  );
}

AgentStatusState? _normalizeCodexState(String eventName) {
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

AgentStatusState? _normalizeClaudeState(String eventName) {
  return switch (eventName) {
    'UserPromptSubmit' ||
    'PreToolUse' ||
    'PostToolUse' ||
    'PostToolUseFailure' => AgentStatusState.working,
    'PermissionRequest' => AgentStatusState.waiting,
    'Stop' => AgentStatusState.done,
    _ => null,
  };
}

String? _hookEventName(AgentHookEvent event) {
  final explicit = _readFirstString(
    <String, Object?>{'hookEventName': event.hookEventName},
    const <String>['hookEventName'],
  );
  return explicit ??
      _readFirstString(event.payload, const <String>[
        'hook_event_name',
        'hookEventName',
        'hook_type',
        'hookType',
      ]);
}

String _extractPrompt(Map<String, Object?> payload) {
  return _readFirstString(payload, const <String>[
        'prompt',
        'user_prompt',
        'userPrompt',
        'initial_prompt',
        'initialPrompt',
        'user_message',
        'userMessage',
        'message',
      ]) ??
      '';
}

_ToolSnapshot _extractToolSnapshot(AgentHookEvent event) {
  final eventName = _hookEventName(event);
  if (eventName == null) {
    return const _ToolSnapshot();
  }
  final payload = event.payload;
  final hasToolEvent =
      eventName == 'PreToolUse' ||
      eventName == 'PostToolUse' ||
      eventName == 'PostToolUseFailure' ||
      eventName == 'PermissionRequest';
  String? toolName;
  String? toolInput;
  var hasToolInput = false;
  if (hasToolEvent) {
    toolName = _readFirstString(payload, const <String>['tool_name', 'name']);
    for (final key in const <String>['tool_input', 'input', 'arguments']) {
      if (payload.containsKey(key)) {
        hasToolInput = true;
        toolInput = _deriveToolInputPreview(toolName, payload[key]);
        if (toolInput != null) {
          break;
        }
      }
    }
  }

  final lastAssistantMessage =
      _readFirstString(payload, const <String>[
        'last_assistant_message',
        'lastAssistantMessage',
      ]) ??
      _extractToolResponseText(payload['tool_response']) ??
      _readFirstString(payload, const <String>['error']);

  return _ToolSnapshot(
    toolName: toolName,
    toolInput: toolInput,
    lastAssistantMessage: lastAssistantMessage,
    hasToolUpdate: hasToolEvent,
    hasToolInput: hasToolInput,
  );
}

String? _deriveToolInputPreview(String? toolName, Object? input) {
  if (input is String) {
    return _normalizeSingleLine(input, 160);
  }
  if (input is Map) {
    final keys = <String>[
      ...?_toolInputKeysByTool[toolName],
      'file_path',
      'filePath',
      'path',
      'command',
      'cmd',
      'pattern',
      'query',
      'url',
    ];
    for (final key in keys) {
      final value = input[key];
      if (value is String && value.trim().isNotEmpty) {
        return _normalizeSingleLine(value, 160);
      }
      if (value is List && value.isNotEmpty) {
        return _normalizeSingleLine(value.join(', '), 160);
      }
    }
  }
  try {
    return _normalizeSingleLine(jsonEncode(input), 160);
  } catch (_) {
    return null;
  }
}

String? _extractToolResponseText(Object? response) {
  if (response is String && response.trim().isNotEmpty) {
    return _normalizeMultiline(response, 8000);
  }
  if (response is Map) {
    final text = _readFirstString(Map<String, Object?>.from(response), const [
      'text',
      'content',
      'message',
      'error',
    ]);
    if (text != null) {
      return _normalizeMultiline(text, 8000);
    }
  }
  return null;
}

bool _isInterrupted(AgentHookEvent event) {
  final value = event.payload['is_interrupt'] ?? event.payload['interrupted'];
  return value == true;
}

String? _readFirstString(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    if (value is String) {
      final normalized = _normalizeSingleLine(value, 200);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
  }
  return null;
}

String _normalizeSingleLine(String value, int maxLength) {
  final normalized = value.trim().replaceAll(
    RegExp(r'[\r\n\u2028\u2029]+'),
    ' ',
  );
  return normalized.length <= maxLength
      ? normalized
      : normalized.substring(0, maxLength);
}

String _normalizeMultiline(String value, int maxLength) {
  final normalized = value
      .trim()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[\u2028\u2029]'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return normalized.length <= maxLength
      ? normalized
      : normalized.substring(0, maxLength);
}

const Map<String, List<String>> _toolInputKeysByTool = <String, List<String>>{
  'Bash': <String>['command'],
  'Execute': <String>['command'],
  'Read': <String>['file_path', 'filePath', 'path'],
  'Write': <String>['file_path', 'filePath', 'path'],
  'Edit': <String>['file_path', 'filePath', 'path'],
  'MultiEdit': <String>['file_path', 'filePath', 'path'],
  'Grep': <String>['pattern'],
  'Glob': <String>['pattern'],
  'WebFetch': <String>['url'],
  'WebSearch': <String>['query'],
};

class _ToolSnapshot {
  const _ToolSnapshot({
    this.toolName,
    this.toolInput,
    this.lastAssistantMessage,
    this.hasToolUpdate = false,
    this.hasToolInput = false,
  });

  final String? toolName;
  final String? toolInput;
  final String? lastAssistantMessage;
  final bool hasToolUpdate;
  final bool hasToolInput;
}
