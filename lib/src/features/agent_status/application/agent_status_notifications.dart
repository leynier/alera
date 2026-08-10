import 'dart:convert';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';

part 'agent_status_notification_grouping.dart';

typedef AgentStatusNotificationSelectionHandler = void Function(String payload);

abstract interface class AgentStatusNotificationPresenter {
  Future<void> initialize({
    required AgentStatusNotificationSelectionHandler onSelected,
  });

  Future<void> show(AgentStatusNotification notification);
}

class AgentStatusNotification {
  const AgentStatusNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final String payload;
}

class AgentStatusNotificationPayload {
  const AgentStatusNotificationPayload({
    required this.terminalSessionId,
    required this.workspaceId,
    required this.tabId,
    required this.agentType,
    required this.state,
  });

  final String terminalSessionId;
  final String workspaceId;
  final String tabId;
  final AgentType agentType;
  final AgentStatusState state;

  String encode() => jsonEncode(<String, String>{
    'terminalSessionId': terminalSessionId,
    'workspaceId': workspaceId,
    'tabId': tabId,
    'agentType': agentType.key,
    'state': state.key,
  });
}

AgentStatusNotificationPayload? decodeAgentStatusNotificationPayload(
  String? payload,
) {
  if (payload == null || payload.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      return null;
    }
    final record = Map<String, Object?>.from(decoded);
    final terminalSessionId = _requiredString(record['terminalSessionId']);
    final workspaceId = _requiredString(record['workspaceId']);
    final tabId = _requiredString(record['tabId']);
    final agentType = _agentType(record['agentType']);
    final state = _state(record['state']);
    if (terminalSessionId == null ||
        workspaceId == null ||
        tabId == null ||
        agentType == null ||
        state == null) {
      return null;
    }
    return AgentStatusNotificationPayload(
      terminalSessionId: terminalSessionId,
      workspaceId: workspaceId,
      tabId: tabId,
      agentType: agentType,
      state: state,
    );
  } catch (_) {
    return null;
  }
}

/// How long the same terminal must stay quiet before the same state notifies
/// again.
///
/// Agents re-enter `waiting` once per approval and `done` once per turn, and
/// the runtime snapshot can restate a transition the local hook already
/// reported, so without a floor a single task turns into a column of
/// notifications.
const Duration agentStatusNotificationCooldown = Duration(seconds: 60);

class AgentStatusNotificationTracker {
  AgentStatusNotificationTracker({
    required this.now,
    required this.notifiableFrom,
    this.cooldown = agentStatusNotificationCooldown,
  });

  final DateTime Function() now;

  /// States that started before this are what the runtime was already holding
  /// when the coordinator came up, not events the user just caused.
  final DateTime notifiableFrom;

  final Duration cooldown;

  /// Last delivery per terminal session and state. The state start time is
  /// deliberately absent from the key: the local hook path and the runtime
  /// snapshot time the same transition differently, and an agent that flaps
  /// `done -> working -> done` restamps it on every bounce.
  final Map<(String, AgentStatusState), DateTime> _lastNotifiedAt =
      <(String, AgentStatusState), DateTime>{};

  List<AgentStatusEntry> pendingNotifications({
    required Map<String, AgentStatusEntry>? previous,
    required Map<String, AgentStatusEntry> next,
    required bool includeFinished,
  }) {
    final deliveredAt = now();
    _forgetClosedSessions(next);
    final pending = <AgentStatusEntry>[];
    for (final entry in next.values) {
      if (!_isNotifiableState(entry.state, includeFinished: includeFinished)) {
        continue;
      }
      if (entry.stateStartedAt.isBefore(notifiableFrom)) {
        continue;
      }
      final prior = previous?[entry.terminalSessionId];
      if (prior != null &&
          prior.state == entry.state &&
          prior.stateStartedAt == entry.stateStartedAt) {
        continue;
      }
      final key = (entry.terminalSessionId, entry.state);
      if (_lastNotifiedAt[key] case final previousDelivery?) {
        if (deliveredAt.difference(previousDelivery) < cooldown) {
          continue;
        }
      }
      _lastNotifiedAt[key] = deliveredAt;
      pending.add(entry);
    }
    return pending;
  }

  /// Keeps the delivery map bounded: a terminal that is gone cannot repeat.
  void _forgetClosedSessions(Map<String, AgentStatusEntry> next) {
    _lastNotifiedAt.removeWhere((key, _) => !next.containsKey(key.$1));
  }
}

AgentStatusNotification? composeAgentStatusNotification({
  required AgentStatusEntry entry,
  required bool includeFinished,
  String? projectName,
  String? workspaceName,
  String? tabTitle,
}) {
  if (!_isNotifiableState(entry.state, includeFinished: includeFinished)) {
    return null;
  }
  final agent = _agentLabel(entry.agentType);
  final title = switch (entry.state) {
    AgentStatusState.waiting ||
    AgentStatusState.blocked => '$agent needs attention',
    AgentStatusState.done => '$agent finished',
    // coverage:ignore-start
    // _isNotifiableState excludes working entries before notification compose.
    AgentStatusState.working => agent,
    // coverage:ignore-end
  };
  final body = _notificationLocationBody(
    projectName: projectName,
    workspaceName: workspaceName,
    tabTitle: tabTitle,
  );
  return AgentStatusNotification(
    id: _notificationId(entry),
    title: title,
    body: body,
    payload: _encodePayload(entry),
  );
}

String _agentLabel(AgentType agentType) {
  return switch (agentType) {
    AgentType.codex => 'Codex',
    AgentType.claude => 'Claude',
    AgentType.copilot => 'GitHub Copilot',
    AgentType.cursor => 'Cursor',
    AgentType.agy => 'Antigravity',
    AgentType.opencode => 'OpenCode',
    AgentType.opencode2 => 'OpenCode 2',
    AgentType.pi => 'Pi',
    AgentType.amp => 'Amp',
    AgentType.grok => 'Grok Build',
  };
}

String _encodePayload(AgentStatusEntry entry) {
  return AgentStatusNotificationPayload(
    terminalSessionId: entry.terminalSessionId,
    workspaceId: entry.workspaceId,
    tabId: entry.tabId,
    agentType: entry.agentType,
    state: entry.state,
  ).encode();
}

bool _isNotifiableState(
  AgentStatusState state, {
  required bool includeFinished,
}) {
  return switch (state) {
    AgentStatusState.waiting || AgentStatusState.blocked => true,
    AgentStatusState.done => includeFinished,
    AgentStatusState.working => false,
  };
}

String _notificationKey(AgentStatusEntry entry) {
  return [
    entry.terminalSessionId,
    entry.state.key,
    entry.stateStartedAt.toIso8601String(),
  ].join('|');
}

int _notificationId(AgentStatusEntry entry) {
  return _fnv1a(_notificationKey(entry));
}

int _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

String _notificationLocationBody({
  String? projectName,
  String? workspaceName,
  String? tabTitle,
}) {
  final project = projectName?.trim() ?? '';
  final workspace = workspaceName?.trim() ?? '';
  // A workspace named after its project reads as "Workspace alera in alera".
  if (workspace.isNotEmpty &&
      project.isNotEmpty &&
      workspace.toLowerCase() != project.toLowerCase()) {
    return 'Workspace $workspace in $project';
  }
  if (workspace.isNotEmpty) {
    return 'Workspace $workspace';
  }
  final tab = tabTitle?.trim() ?? '';
  if (tab.isNotEmpty) {
    return 'Terminal $tab';
  }
  return 'Open Alera';
}

String? _requiredString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

AgentType? _agentType(Object? value) {
  for (final type in AgentType.values) {
    if (type.key == value) {
      return type;
    }
  }
  return null;
}

AgentStatusState? _state(Object? value) {
  for (final state in AgentStatusState.values) {
    if (state.key == value) {
      return state;
    }
  }
  return null;
}
