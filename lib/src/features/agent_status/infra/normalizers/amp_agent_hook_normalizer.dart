part of '../agent_hook_event_normalizer.dart';

AgentStatusState? _normalizeAmpState(String eventName) {
  return switch (eventName) {
    'session.start' ||
    'agent.start' ||
    'tool.call' ||
    'tool.result' => AgentStatusState.working,
    'agent.end' => AgentStatusState.done,
    _ => null,
  };
}

bool _isAmpNewTurn(String eventName) {
  return eventName == 'agent.start';
}

String? _ampAssistantTextForEvent(AgentHookEvent event, String eventName) {
  if (eventName != 'agent.end') {
    return null;
  }
  return _lastAmpAssistantMessage(event.payload['messages']);
}

String? _lastAmpAssistantMessage(Object? value) {
  if (value is! List) {
    return null;
  }
  for (final message in value.reversed) {
    if (message is! Map) {
      continue;
    }
    final record = Map<String, Object?>.from(message);
    if (record['role'] != 'assistant') {
      continue;
    }
    final text = _ampMessageText(record['content']);
    if (text != null) {
      return text;
    }
  }
  return null;
}

String? _ampMessageText(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return _normalizeMultiline(value, 8000);
  }
  if (value is! List) {
    return null;
  }
  final out = StringBuffer();
  for (final part in value) {
    if (part is! Map) {
      continue;
    }
    final record = Map<String, Object?>.from(part);
    if (record['type'] == 'text') {
      final text = record['text'];
      if (text is String && text.isNotEmpty) {
        out.write(text);
      }
    }
  }
  final normalized = out.toString().trim();
  return normalized.isEmpty ? null : _normalizeMultiline(normalized, 8000);
}

bool _isAmpInterrupted(AgentHookEvent event) {
  return _isGenericInterrupted(event) || event.payload['status'] == 'cancelled';
}
