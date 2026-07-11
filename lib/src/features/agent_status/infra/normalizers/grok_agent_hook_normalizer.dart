part of '../agent_hook_event_normalizer.dart';

AgentStatusState? _normalizeGrokState(
  String eventName,
  Map<String, Object?> payload,
) {
  if (eventName == 'Notification') {
    final message = _readFirstString(payload, const <String>['message']);
    final notificationType = _readFirstString(payload, const <String>[
      'notificationType',
      'notification_type',
      'type',
    ]);
    final level = _readFirstString(payload, const <String>['level']);
    if (_isRoutineGrokPermissionNotification(
      notificationType: notificationType,
      message: message,
      level: level,
    )) {
      return null;
    }
    if (_isGrokIdleNotification(message)) {
      return AgentStatusState.done;
    }
    if (_isGrokPermissionNotification(message)) {
      return AgentStatusState.waiting;
    }
    return null;
  }
  return switch (eventName) {
    'UserPromptSubmit' ||
    'PreToolUse' ||
    'PostToolUse' ||
    'PostToolUseFailure' => AgentStatusState.working,
    'Stop' || 'StopFailure' || 'SessionEnd' => AgentStatusState.done,
    'SessionStart' => null,
    _ => null,
  };
}

bool _isGrokNewTurn(String eventName) => eventName == 'UserPromptSubmit';

String? _normalizeGrokEventName(String? eventName) {
  if (eventName == null) {
    return null;
  }
  final normalized = eventName
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();
  return switch (normalized) {
    'sessionstart' => 'SessionStart',
    'userpromptsubmit' => 'UserPromptSubmit',
    'pretooluse' => 'PreToolUse',
    'posttooluse' => 'PostToolUse',
    'posttoolusefailure' => 'PostToolUseFailure',
    'notification' => 'Notification',
    'stop' => 'Stop',
    'stopfailure' => 'StopFailure',
    'sessionend' => 'SessionEnd',
    _ => eventName,
  };
}

String _stripGrokUserQueryWrapper(String prompt) {
  const opener = '<user_query>';
  if (!prompt.startsWith(opener)) {
    return prompt;
  }
  const closer = '</user_query>';
  var unwrapped = prompt.substring(opener.length);
  if (unwrapped.endsWith(closer)) {
    unwrapped = unwrapped.substring(0, unwrapped.length - closer.length);
  }
  return unwrapped.trim();
}

bool _isRoutineGrokPermissionNotification({
  required String? notificationType,
  required String? message,
  required String? level,
}) {
  return notificationType
              ?.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
              .toLowerCase() ==
          'permissionprompt' &&
      message?.trim().toLowerCase() == 'tool permission requested' &&
      (level == null || level.trim().toLowerCase() == 'info');
}

bool _isGrokPermissionNotification(String? message) {
  if (message == null) {
    return false;
  }
  final lower = message.toLowerCase();
  return const <String>[
    'permission',
    'approval',
    'approve',
    'allow',
    'confirm',
    'needs your',
    'requires your',
    'feedback',
    'clarify',
    'question',
  ].any(lower.contains);
}

bool _isGrokIdleNotification(String? message) {
  if (message == null) {
    return false;
  }
  final lower = message.toLowerCase();
  return const <String>[
    'type your message',
    'enter send',
    'shift-tab normal',
    'ask a side question',
  ].any(lower.contains);
}
