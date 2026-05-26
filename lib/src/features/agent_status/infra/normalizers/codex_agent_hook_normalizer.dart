part of '../agent_hook_event_normalizer.dart';

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

bool _isCodexNewTurn(String eventName) {
  return eventName == 'SessionStart' || eventName == 'UserPromptSubmit';
}
