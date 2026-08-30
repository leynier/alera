part of 'agent_status_notifications.dart';

/// How many locations the grouped body names before it summarises the rest.
const int _groupedBodyNameLimit = 3;

/// An entry together with the workbench names that say where it is running.
class const AgentStatusNotificationLocation({
  required final AgentStatusEntry entry,
  final String? projectName,
  final String? workspaceName,
  final String? tabTitle,
});

/// Collapses a burst into one notification.
///
/// A single location keeps the per-agent copy, because "Claude needs
/// attention" says more than "1 agent needs attention". Two or more collapse,
/// so a fleet of agents settling at once costs one entry in the notification
/// centre instead of one per terminal.
AgentStatusNotification? composeAgentStatusNotifications({
  required List<AgentStatusNotificationLocation> locations,
  required bool includeFinished,
}) {
  final notifiable = locations
      .where(
        (location) => _isNotifiableState(
          location.entry.state,
          includeFinished: includeFinished,
        ),
      )
      .toList();
  if (notifiable.isEmpty) {
    return null;
  }
  if (notifiable.length == 1) {
    final only = notifiable.single;
    return composeAgentStatusNotification(
      entry: only.entry,
      includeFinished: includeFinished,
      projectName: only.projectName,
      workspaceName: only.workspaceName,
      tabTitle: only.tabTitle,
    );
  }
  final finished = notifiable
      .where((location) => location.entry.state == AgentStatusState.done)
      .length;
  final title = switch (finished) {
    0 => '${notifiable.length} agents need attention',
    _ when finished == notifiable.length =>
      '${notifiable.length} agents finished',
    _ => '${notifiable.length} agent updates',
  };
  // Selecting the group opens the terminal that moved last, which is the one
  // the user is most likely reacting to.
  final newest = notifiable.reduce(
    (a, b) => b.entry.updatedAt.isAfter(a.entry.updatedAt) ? b : a,
  );
  return AgentStatusNotification(
    id: _groupedNotificationId,
    title: title,
    body: _groupedLocationBody(notifiable),
    payload: _encodePayload(newest.entry),
  );
}

/// One id for every group, so a newer group replaces the previous one in the
/// notification centre instead of stacking beside it.
final int _groupedNotificationId = _fnv1a('alera.agent-status.group');

String _groupedLocationBody(List<AgentStatusNotificationLocation> locations) {
  final names = <String>[];
  for (final location in locations) {
    final name = _groupedLocationName(location);
    if (!names.contains(name)) {
      names.add(name);
    }
  }
  if (names.length <= _groupedBodyNameLimit) {
    return names.join(', ');
  }
  final shown = names.take(_groupedBodyNameLimit).join(', ');
  return '$shown and ${names.length - _groupedBodyNameLimit} more';
}

/// The long form ("Workspace main in alera") reads as noise once it repeats,
/// so a grouped body names each place as briefly as it can still be told apart.
String _groupedLocationName(AgentStatusNotificationLocation location) {
  final workspace = location.workspaceName?.trim() ?? '';
  if (workspace.isNotEmpty) {
    return workspace;
  }
  final tab = location.tabTitle?.trim() ?? '';
  if (tab.isNotEmpty) {
    return tab;
  }
  return _agentLabel(location.entry.agentType);
}
