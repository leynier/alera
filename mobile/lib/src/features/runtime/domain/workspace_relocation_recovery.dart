import 'workspace_summary.dart';

/// Choices read from the journal, never reconstructed from the current branch.
class const WorkspaceRelocationRecoveryEntry({
  required final String id,
  required final WorkspaceSummary source,
  required final String phase,
  required final bool completed,
  required final bool toProjectCheckout,
  required final bool moveChanges,
  final WorkspaceSummary? destination,
  final String? branch,
  final String? replacementBranch,
  final String? destinationPath,
  final String? workspaceRoot,
  final String? setupAttemptId,
  final bool hasSetupRecipe = false,
  final bool setupFinished = false,
  final bool setupFailed = false,
  final bool setupCancellationRequested = false,
  final List<String> processObservations = const [],
}) {
  String get action => toProjectCheckout ? 'Hand On' : 'Hand Off';

  Map<String, Object?> resumePayload({required bool sharedImpactConfirmed}) {
    if (!sharedImpactConfirmed) {
      throw StateError('Confirm the shared checkout impact before resuming.');
    }
    return {
      'id': source.id,
      'expectedInstanceId': source.instanceId,
      'relocationId': id,
      'sharedImpactConfirmed': true,
      if (!toProjectCheckout) ...{
        'branch': branch,
        'replacementBranch': replacementBranch,
        'reuseExistingBranch': replacementBranch != null,
        'moveChanges': moveChanges,
        if (destinationPath != null) 'path': destinationPath,
        if (workspaceRoot != null) 'workspaceRoot': workspaceRoot,
        'deferSetup': true,
      },
    };
  }
}

class const WorkspaceRelocationRecoverySnapshot({
  required final List<WorkspaceRelocationRecoveryEntry> entries,
  final String? ownerError,
}) {
  factory fromResponse(WorkspaceSummary workspace, Object? response) {
    if (!workspace.isRemote) {
      final entries = _list(response)
          .map((item) => _localEntry(workspace, _map(item)))
          .toList();
      _requireUnique(entries);
      return WorkspaceRelocationRecoverySnapshot(
        entries: List.unmodifiableOf(entries),
      );
    }
    final report = _map(response);
    if (report['kind'] != 'remoteWorkspaceRelocationRecovery') {
      throw const FormatException('Invalid SSH relocation recovery response.');
    }
    _requireIdentity(
      workspace,
      WorkspaceSummary.fromJson(_map(report['workspace'])),
    );
    final owner = report['owner'] == null ? null : _map(report['owner']);
    final ownerError = report['ownerError'] as String?;
    if (owner == null && (ownerError == null || ownerError.isEmpty)) {
      throw const FormatException('Missing owner recovery status.');
    }
    final ownerItems = <String, Map<String, Object?>>{};
    if (owner != null) {
      if (owner['version'] != 1) {
        throw const FormatException('Unsupported owner recovery version.');
      }
      _requireIdentity(
        workspace,
        WorkspaceSummary.fromJson(_map(owner['workspace'])),
        ownerLocal: true,
      );
      for (final raw in _list(owner['items'])) {
        final item = _map(raw);
        final journal = _map(item['relocation']);
        _requireIdentity(
          workspace,
          WorkspaceSummary.fromJson(_map(journal['source'])),
          ownerLocal: true,
        );
        _requireIdentity(
          workspace,
          WorkspaceSummary.fromJson(_map(journal['destination'])),
          ownerLocal: true,
        );
        final id = _text(journal, 'id');
        if (ownerItems.containsKey(id)) {
          throw const FormatException('Duplicate owner relocation ID.');
        }
        ownerItems[id] = item;
      }
    }
    final entries = <WorkspaceRelocationRecoveryEntry>[];
    for (final raw in _list(report['homeIntents'])) {
      final record = _map(raw);
      final retained = _map(record['intent']);
      final source = WorkspaceSummary.fromJson(_map(retained['source']));
      _requireIdentity(workspace, source);
      final choices = _map(retained['intent']);
      if (choices['workspaceId'] != workspace.id) {
        throw const FormatException(
          'Relocation choices belong to another task.',
        );
      }
      final id = _text(retained, 'id');
      final ownerItem = ownerItems[id];
      final journal = ownerItem == null ? null : _map(ownerItem['relocation']);
      final setup = ownerItem?['setup'] == null
          ? null
          : _map(ownerItem!['setup']);
      final completed = _boolean(record, 'homeCommitted');
      entries.add(
        WorkspaceRelocationRecoveryEntry(
          id: id,
          source: source,
          phase:
              journal?['phase'] as String? ??
              (completed ? 'completed' : 'awaitingOwner'),
          completed: completed,
          toProjectCheckout: _boolean(choices, 'toProjectCheckout'),
          moveChanges: _boolean(choices, 'moveChanges'),
          branch: choices['branch'] as String?,
          replacementBranch: choices['replacementBranch'] as String?,
          destinationPath: choices['destinationPath'] as String?,
          workspaceRoot: retained['workspaceRoot'] as String?,
          hasSetupRecipe: setup != null,
          setupAttemptId: setup?['attemptId'] as String?,
          setupFinished: setup?['report'] != null,
          setupFailed: _setupFailed(setup),
          setupCancellationRequested:
              ownerItem?['setupCancellationRequested'] == true,
          processObservations: _observations(ownerItem),
        ),
      );
    }
    _requireUnique(entries);
    return WorkspaceRelocationRecoverySnapshot(
      entries: List.unmodifiableOf(entries),
      ownerError: ownerError,
    );
  }
}

WorkspaceRelocationRecoveryEntry _localEntry(
  WorkspaceSummary workspace,
  Map<String, Object?> item,
) {
  final journal = _map(item['relocation']);
  final source = WorkspaceSummary.fromJson(_map(journal['source']));
  final destination = WorkspaceSummary.fromJson(_map(journal['destination']));
  _requireIdentity(workspace, source);
  _requireIdentity(workspace, destination);
  final phase = _text(journal, 'phase');
  final setup = item['setup'] == null ? null : _map(item['setup']);
  return WorkspaceRelocationRecoveryEntry(
    id: _text(journal, 'id'),
    source: source,
    destination: destination,
    phase: phase,
    completed: phase == 'completed',
    toProjectCheckout: destination.isMain,
    moveChanges: _boolean(journal, 'moveChanges'),
    branch: destination.isMain ? null : destination.branch,
    replacementBranch: journal['replacementBranch'] as String?,
    destinationPath: destination.isMain ? null : destination.path,
    hasSetupRecipe: setup != null,
    setupAttemptId: setup?['attemptId'] as String?,
    setupFinished: setup?['report'] != null,
    setupFailed: _setupFailed(setup),
    setupCancellationRequested: item['setupCancellationRequested'] == true,
    processObservations: _observations(item),
  );
}

void _requireIdentity(
  WorkspaceSummary expected,
  WorkspaceSummary actual, {
  bool ownerLocal = false,
}) {
  if (actual.id != expected.id ||
      actual.instanceId == null ||
      actual.instanceId != expected.instanceId ||
      actual.projectId != expected.projectId ||
      actual.hostId != (ownerLocal ? 'local' : expected.hostId)) {
    throw const FormatException(
      'Relocation history belongs to another task instance or host.',
    );
  }
}

bool _setupFailed(Map<String, Object?>? setup) {
  if (setup?['report'] == null) return false;
  return _list(_map(setup!['report'])['steps'])
      .any((step) => _map(step)['succeeded'] != true);
}

List<String> _observations(Map<String, Object?>? item) => List.unmodifiableOf(
  _list(item?['setupRootObservations'] ?? const []).map((raw) {
    final observation = _map(raw);
    return '${_text(observation, 'state')}: ${_text(observation, 'reason')}';
  }),
);

void _requireUnique(List<WorkspaceRelocationRecoveryEntry> entries) {
  if (entries.map((entry) => entry.id).toSet().length != entries.length) {
    throw const FormatException('Duplicate relocation ID.');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid relocation recovery object.');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value) {
  if (value is! List) {
    throw const FormatException('Invalid relocation recovery list.');
  }
  return List<Object?>.from(value);
}

String _text(Map<String, Object?> value, String key) {
  final text = value[key];
  if (text is! String || text.isEmpty) {
    throw FormatException('Missing relocation $key.');
  }
  return text;
}

bool _boolean(Map<String, Object?> value, String key) {
  final flag = value[key];
  if (flag is! bool) throw FormatException('Missing relocation $key.');
  return flag;
}
