part of '../agent_hook_event_normalizer.dart';

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
  if (input is List) {
    final preview = _deriveQuestionListPreview(input);
    if (preview != null) {
      return preview;
    }
    if (input.isNotEmpty) {
      return _normalizeSingleLine(input.join(', '), 160);
    }
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
        if (key == 'questions') {
          final preview = _deriveQuestionListPreview(value);
          if (preview != null) {
            return preview;
          }
        }
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

String? _deriveQuestionListPreview(List<Object?> questions) {
  for (final question in questions) {
    if (question is String && question.trim().isNotEmpty) {
      return _normalizeSingleLine(question, 160);
    }
    if (question is Map) {
      final text = _readFirstString(
        Map<String, Object?>.from(question),
        const <String>['question', 'Question', 'prompt', 'Prompt'],
      );
      if (text != null) {
        return text;
      }
    }
  }
  return null;
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
