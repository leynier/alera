import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';

part 'normalizers/agy_agent_hook_normalizer.dart';
part 'normalizers/amp_agent_hook_normalizer.dart';
part 'normalizers/claude_agent_hook_normalizer.dart';
part 'normalizers/codex_agent_hook_normalizer.dart';
part 'normalizers/copilot_agent_hook_normalizer.dart';
part 'normalizers/cursor_agent_hook_normalizer.dart';
part 'normalizers/opencode_agent_hook_normalizer.dart';
part 'normalizers/pi_agent_hook_normalizer.dart';

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
  final toolSnapshot = _extractToolSnapshot(event, eventName: eventName);
  final state = switch (event.agentType) {
    AgentType.codex => _normalizeCodexState(eventName),
    AgentType.claude => _normalizeClaudeState(eventName),
    AgentType.copilot => _normalizeCopilotState(
      eventName,
      event.payload,
      toolSnapshot.toolName,
    ),
    AgentType.cursor => _normalizeCursorState(eventName, previous),
    AgentType.agy => _normalizeAgyState(eventName, toolSnapshot.toolName),
    AgentType.opencode => _normalizeOpenCodeState(eventName),
    AgentType.pi => _normalizePiState(eventName),
    AgentType.amp => _normalizeAmpState(eventName),
  };
  if (state == null) {
    return null;
  }

  final isNewTurn = _isNewTurn(event.agentType, eventName);
  final prompt = _extractPromptForEvent(event, eventName);
  final interrupted = state == AgentStatusState.done && _isInterrupted(event)
      ? true
      : event.agentType == AgentType.cursor &&
            eventName == 'afterAgentResponse' &&
            previous?.state == AgentStatusState.done
      ? previous?.interrupted
      : null;
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
    interrupted: interrupted,
  );
}

String? _hookEventName(AgentHookEvent event) {
  final explicit = _readFirstString(
    <String, Object?>{'hookEventName': event.hookEventName},
    const <String>['hookEventName'],
  );
  final raw =
      explicit ??
      _readFirstString(event.payload, const <String>[
        'hook_event_name',
        'hookEventName',
        'hook_type',
        'hookType',
      ]);
  if (event.agentType == AgentType.copilot) {
    return _normalizeCopilotEventName(
      raw ?? _inferCopilotEventName(event.payload),
    );
  }
  return raw;
}

bool _isNewTurn(AgentType agentType, String eventName) {
  return switch (agentType) {
    AgentType.codex => _isCodexNewTurn(eventName),
    AgentType.claude => _isClaudeNewTurn(eventName),
    AgentType.copilot => _isCopilotNewTurn(eventName),
    AgentType.cursor => _isCursorNewTurn(eventName),
    AgentType.agy => _isAgyNewTurn(eventName),
    AgentType.opencode => _isOpenCodeNewTurn(eventName),
    AgentType.pi => _isPiNewTurn(eventName),
    AgentType.amp => _isAmpNewTurn(eventName),
  };
}

String _extractPromptForEvent(AgentHookEvent event, String eventName) {
  if (event.agentType == AgentType.copilot && eventName == 'Notification') {
    return '';
  }
  if (event.agentType == AgentType.opencode) {
    final prompt = _openCodePromptForEvent(event, eventName);
    if (prompt != null) {
      return prompt;
    }
  }
  final direct = _extractPrompt(event.payload);
  if (direct.isNotEmpty) {
    return direct;
  }
  if (event.agentType == AgentType.agy) {
    return _agyPromptForEvent(event) ?? '';
  }
  return '';
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

_ToolSnapshot _extractToolSnapshot(
  AgentHookEvent event, {
  required String eventName,
}) {
  if (event.agentType == AgentType.cursor) {
    return _extractCursorToolSnapshot(event, eventName);
  }
  final payload = event.payload;
  final hasToolEvent =
      eventName == 'PreToolUse' ||
      eventName == 'PostToolUse' ||
      eventName == 'PostToolUseFailure' ||
      eventName == 'PermissionRequest' ||
      eventName == 'tool_call' ||
      eventName == 'tool_execution_start' ||
      eventName == 'tool_execution_end' ||
      eventName == 'tool.call' ||
      eventName == 'tool.result';
  String? toolName;
  String? toolInput;
  var hasToolInput = false;
  if (hasToolEvent) {
    final nestedToolCall = event.agentType == AgentType.agy
        ? _readAgyToolCall(payload)
        : event.agentType == AgentType.copilot
        ? _readCopilotToolCall(payload)
        : const _NestedToolCall();
    toolName =
        _readFirstString(payload, const <String>[
          'tool_name',
          'toolName',
          'name',
          'tool',
        ]) ??
        nestedToolCall.toolName;
    for (final key in const <String>[
      'tool_input',
      'toolInput',
      'toolArgs',
      'input',
      'arguments',
    ]) {
      if (payload.containsKey(key)) {
        hasToolInput = true;
        toolInput = _deriveToolInputPreview(toolName, payload[key]);
        if (toolInput != null) {
          break;
        }
      }
    }
    if (toolInput == null && nestedToolCall.toolInputSource != null) {
      hasToolInput = true;
      toolInput = _deriveToolInputPreview(
        toolName,
        nestedToolCall.toolInputSource,
      );
    }
  }

  final lastAssistantMessage =
      _assistantTextFromHookEvent(event, eventName) ??
      _readFirstString(payload, const <String>[
        'last_assistant_message',
        'lastAssistantMessage',
        'message',
      ]) ??
      (eventName == 'Notification'
          ? _readFirstString(payload, const <String>['body', 'text', 'title'])
          : null) ??
      _extractToolResponseText(payload['tool_response']) ??
      _extractToolResponseText(payload['toolResponse']) ??
      _extractToolResponseText(payload['tool_result']) ??
      _extractToolResponseText(payload['toolResult']) ??
      _readFirstString(payload, const <String>[
        'error_message',
        'errorMessage',
        'error',
      ]) ??
      ((eventName == 'Stop')
          ? _readLastAssistantFromTranscript(
              payload['transcript_path'] ?? payload['transcriptPath'],
            )
          : null);

  return _ToolSnapshot(
    toolName: toolName,
    toolInput: toolInput,
    lastAssistantMessage: lastAssistantMessage,
    hasToolUpdate: hasToolEvent,
    hasToolInput: hasToolInput,
  );
}

String? _assistantTextFromHookEvent(AgentHookEvent event, String eventName) {
  return switch (event.agentType) {
    AgentType.opencode => _openCodeAssistantTextForEvent(event, eventName),
    AgentType.pi => _piAssistantTextForEvent(event, eventName),
    AgentType.amp => _ampAssistantTextForEvent(event, eventName),
    AgentType.codex ||
    AgentType.claude ||
    AgentType.copilot ||
    AgentType.cursor ||
    AgentType.agy => null,
  };
}

Map<String, Object?>? _parseJsonObjectString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
  } catch (_) {}
  return null;
}

String? _deriveToolInputPreview(String? toolName, Object? input) {
  if (input is String) {
    return _normalizeSingleLine(input, 160);
  }
  if (input is Map) {
    final keys = <String>[
      ...?_toolInputKeysByTool[toolName],
      'question',
      'questions',
      'Prompt',
      'Action',
      'Target',
      'Reason',
      'CommandLine',
      'AbsolutePath',
      'TargetFile',
      'DirectoryPath',
      'SearchPath',
      'Query',
      'Url',
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

String? _readLastAssistantFromTranscript(Object? transcriptPath) {
  return _readLastTextFromTranscript(transcriptPath, _assistantTextFromLine);
}

String? _readLastUserPromptFromTranscript(Object? transcriptPath) {
  return _readLastTextFromTranscript(transcriptPath, _userPromptTextFromLine);
}

String? _readLastTextFromTranscript(
  Object? transcriptPath,
  String? Function(String line) extract,
) {
  if (transcriptPath is! String || transcriptPath.trim().isEmpty) {
    return null;
  }
  try {
    final file = File(transcriptPath);
    final length = file.lengthSync();
    if (length <= 0) {
      return null;
    }
    final start = length > _transcriptMaxScanBytes
        ? length - _transcriptMaxScanBytes
        : 0;
    final bytes = file.openSync()..setPositionSync(start);
    try {
      final text = utf8.decode(
        bytes.readSync(length - start),
        allowMalformed: true,
      );
      final lines = text.split('\n');
      for (var index = lines.length - 1; index >= 0; index--) {
        final line = lines[index].trim();
        if (line.isEmpty) {
          continue;
        }
        final extracted = extract(line);
        if (extracted != null) {
          return _normalizeMultiline(extracted, 8000);
        }
      }
    } finally {
      bytes.closeSync();
    }
  } catch (_) {}
  return null;
}

String? _assistantTextFromLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      return null;
    }
    final record = Map<String, Object?>.from(decoded);
    if (record['type'] == 'assistant.message' && record['data'] is Map) {
      final data = Map<String, Object?>.from(record['data'] as Map);
      return _assistantContentText(data['content']);
    }
    if (record['source'] == 'MODEL' &&
        record['type'] == 'PLANNER_RESPONSE' &&
        record['content'] is String) {
      return record['content'] as String;
    }
    final message = record['message'] is Map
        ? Map<String, Object?>.from(record['message'] as Map)
        : null;
    final role = record['role'] ?? message?['role'];
    if (role != 'assistant' && record['type'] != 'assistant') {
      return null;
    }
    return _assistantContentText(message?['content'] ?? record['content']);
  } catch (_) {
    return null;
  }
}

String? _assistantContentText(Object? content) {
  if (content is String && content.trim().isNotEmpty) {
    return content;
  }
  if (content is List) {
    for (final part in content) {
      if (part is Map && part['text'] is String) {
        final text = part['text'] as String;
        if (text.trim().isNotEmpty) {
          return text;
        }
      }
    }
  }
  return null;
}

String? _userPromptTextFromLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      return null;
    }
    final record = Map<String, Object?>.from(decoded);
    final source = record['source'];
    final type = record['type'];
    final content = record['content'];
    if ((source == 'USER_EXPLICIT' || source == 'USER') &&
        (type == 'USER_INPUT' || type == 'REQUEST') &&
        content is String) {
      final match = RegExp(
        r'<USER_REQUEST>\s*([\s\S]*?)\s*</USER_REQUEST>',
      ).firstMatch(content);
      final text = (match?.group(1) ?? content).trim();
      return text.isEmpty ? null : text;
    }
  } catch (_) {}
  return null;
}

bool _isInterrupted(AgentHookEvent event) {
  return switch (event.agentType) {
    AgentType.amp => _isAmpInterrupted(event),
    AgentType.cursor => _isCursorInterrupted(event),
    AgentType.codex ||
    AgentType.claude ||
    AgentType.copilot ||
    AgentType.agy ||
    AgentType.opencode ||
    AgentType.pi => _isGenericInterrupted(event),
  };
}

bool _isGenericInterrupted(AgentHookEvent event) {
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
  'run_command': <String>['CommandLine', 'command'],
  'ask_question': <String>['Prompt', 'question'],
  'ask_permission': <String>['Action', 'Target', 'Reason'],
  'bash': <String>['command'],
  'read': <String>['file_path', 'filePath', 'path'],
  'write': <String>['file_path', 'filePath', 'path'],
  'edit': <String>['file_path', 'filePath', 'path'],
};

const int _transcriptMaxScanBytes = 4 * 1000 * 1000;

class _NestedToolCall {
  const _NestedToolCall({this.toolName, this.toolInputSource});

  final String? toolName;
  final Object? toolInputSource;
}

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
