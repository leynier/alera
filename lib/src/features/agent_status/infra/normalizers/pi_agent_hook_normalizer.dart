part of '../agent_hook_event_normalizer.dart';

AgentStatusState? _normalizePiState(String eventName) {
  return switch (eventName) {
    'before_agent_start' ||
    'agent_start' ||
    'tool_call' ||
    'tool_execution_start' ||
    'tool_execution_end' ||
    'message_end' => AgentStatusState.working,
    'agent_end' || 'session_shutdown' => AgentStatusState.done,
    _ => null,
  };
}

bool _isPiNewTurn(String eventName) {
  return eventName == 'before_agent_start';
}

String? _piAssistantTextForEvent(AgentHookEvent event, String eventName) {
  if (eventName != 'message_end' || event.payload['role'] != 'assistant') {
    return null;
  }
  final value = event.payload['text'];
  if (value is String && value.trim().isNotEmpty) {
    return _normalizeMultiline(value, 8000);
  }
  return null;
}
