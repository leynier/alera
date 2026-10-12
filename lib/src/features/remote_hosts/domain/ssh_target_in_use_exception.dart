/// `sshTargetInUse`: the host still has workspaces or project checkouts, so
/// the runtime refused to forget it.
final class const SshTargetInUseException({
  required final String hostId,
  required final String alias,
  final int workspaceCount = 0,
  final int checkoutCount = 0,
  final List<String> projectIds = const <String>[],
  final List<String> remoteOnlyProjectIds = const <String>[],
}) implements Exception {
  factory fromDetails(Map<String, Object?> details, {String? fallbackAlias}) {
    return SshTargetInUseException(
      hostId: _string(details['hostId']) ?? '',
      alias: _string(details['alias']) ?? fallbackAlias ?? '',
      workspaceCount: _int(details['workspaceCount']),
      checkoutCount: _int(details['checkoutCount']),
      projectIds: _strings(details['projectIds']),
      remoteOnlyProjectIds: _strings(details['remoteOnlyProjectIds']),
    );
  }

  int get projectCount =>
      projectIds.isNotEmpty ? projectIds.length : checkoutCount;

  @override
  String toString() {
    final parts = <String>[
      if (projectCount > 0) _count(projectCount, 'project'),
      if (workspaceCount > 0) _count(workspaceCount, 'workspace'),
    ];
    final name = alias.isEmpty ? 'This host' : alias;
    if (parts.isEmpty) {
      return '$name is still in use. Remove its projects and workspaces first.';
    }
    return '$name still has ${parts.join(' and ')}. Remove them first.';
  }
}

/// `hostBusy`: restarting the host's runtime would close terminals that are
/// still open there. Retrying with `force` closes them.
final class const HostBusyException({
  required final String hostId,
  required final String alias,
  final int activeSessions = 0,
  final List<String> sessionIds = const <String>[],
}) implements Exception {
  factory fromDetails(Map<String, Object?> details, {String? fallbackAlias}) {
    final sessionIds = _strings(details['sessionIds']);
    final active = _int(details['activeSessions']);
    return HostBusyException(
      hostId: _string(details['hostId']) ?? '',
      alias: _string(details['alias']) ?? fallbackAlias ?? '',
      activeSessions: active > 0 ? active : sessionIds.length,
      sessionIds: sessionIds,
    );
  }

  @override
  String toString() {
    final name = alias.isEmpty ? 'this host' : alias;
    return '${_count(activeSessions, 'terminal')} on $name would close.';
  }
}

String _count(int count, String noun) =>
    count == 1 ? '1 $noun' : '$count ${noun}s';

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

List<String> _strings(Object? value) => value is List
    ? List<String>.unmodifiableOf(value.whereType<String>())
    : const <String>[];
