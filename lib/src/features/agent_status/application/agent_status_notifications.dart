import 'dart:convert';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';

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

class AgentStatusNotificationTracker {
  final Set<String> _delivered = <String>{};

  List<AgentStatusEntry> pendingNotifications({
    required Map<String, AgentStatusEntry>? previous,
    required Map<String, AgentStatusEntry> next,
  }) {
    final pending = <AgentStatusEntry>[];
    for (final entry in next.values) {
      if (!_isNotifiableState(entry.state)) {
        continue;
      }
      final prior = previous?[entry.terminalSessionId];
      if (prior != null &&
          prior.state == entry.state &&
          prior.stateStartedAt == entry.stateStartedAt) {
        continue;
      }
      final key = _notificationKey(entry);
      if (!_delivered.add(key)) {
        continue;
      }
      pending.add(entry);
    }
    return pending;
  }
}

AgentStatusNotification? composeAgentStatusNotification({
  required AgentStatusEntry entry,
  String? projectName,
  String? workspaceName,
  String? tabTitle,
}) {
  if (!_isNotifiableState(entry.state)) {
    return null;
  }
  final agent = switch (entry.agentType) {
    AgentType.codex => 'Codex',
    AgentType.claude => 'Claude',
    AgentType.copilot => 'GitHub Copilot',
    AgentType.cursor => 'Cursor',
    AgentType.agy => 'Antigravity',
    AgentType.opencode => 'OpenCode',
    AgentType.pi => 'Pi',
    AgentType.amp => 'Amp',
    AgentType.grok => 'Grok Build',
  };
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
  final payload = AgentStatusNotificationPayload(
    terminalSessionId: entry.terminalSessionId,
    workspaceId: entry.workspaceId,
    tabId: entry.tabId,
    agentType: entry.agentType,
    state: entry.state,
  ).encode();
  return AgentStatusNotification(
    id: _notificationId(entry),
    title: title,
    body: body,
    payload: payload,
  );
}

bool _isNotifiableState(AgentStatusState state) {
  return state == AgentStatusState.waiting ||
      state == AgentStatusState.blocked ||
      state == AgentStatusState.done;
}

String _notificationKey(AgentStatusEntry entry) {
  return [
    entry.terminalSessionId,
    entry.state.key,
    entry.stateStartedAt.toIso8601String(),
  ].join('|');
}

int _notificationId(AgentStatusEntry entry) {
  var hash = 0x811c9dc5;
  for (final codeUnit in _notificationKey(entry).codeUnits) {
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
  if (workspace.isNotEmpty && project.isNotEmpty) {
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
