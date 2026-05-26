part of '../agent_hook_event_normalizer.dart';

AgentStatusState? _normalizeOpenCodeState(String eventName) {
  return switch (eventName) {
    'SessionBusy' || 'MessagePart' => AgentStatusState.working,
    'PermissionRequest' || 'AskUserQuestion' => AgentStatusState.waiting,
    'SessionIdle' => AgentStatusState.done,
    _ => null,
  };
}

bool _isOpenCodeNewTurn(String eventName) => false;

String? _openCodePromptForEvent(AgentHookEvent event, String eventName) {
  if (eventName != 'MessagePart' || event.payload['role'] != 'user') {
    return null;
  }
  return _readFirstString(event.payload, const <String>['text']) ?? '';
}

String? _openCodeAssistantTextForEvent(AgentHookEvent event, String eventName) {
  if (eventName != 'MessagePart' || event.payload['role'] != 'assistant') {
    return null;
  }
  final value = event.payload['text'];
  if (value is String && value.trim().isNotEmpty) {
    return _normalizeMultiline(value, 8000);
  }
  return null;
}
