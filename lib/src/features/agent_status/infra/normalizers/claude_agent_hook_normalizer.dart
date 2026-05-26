part of '../agent_hook_event_normalizer.dart';

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

bool _isClaudeNewTurn(String eventName) {
  return eventName == 'UserPromptSubmit';
}
