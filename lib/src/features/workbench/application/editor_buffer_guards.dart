part of 'workspace_file_service.dart';

class EditorBufferGuardRuntimeHandler(final EditorSessionRegistry registry)
    implements RuntimeBufferGuardHandler {
  @override
  List<Map<String, Object?>> lock({
    required String guardId,
    required Set<String> tabIds,
    required Set<String> workspacePaths,
  }) => registry
      .acquireBufferGuard(
        guardId,
        EditorBufferGuardScope(tabIds: tabIds, workspacePaths: workspacePaths),
      )
      .map(
        (blocker) => <String, Object?>{
          'tabId': blocker.tabId,
          'path': blocker.path,
          'reason': blocker.reason,
        },
      )
      .toList();

  @override
  void release(String guardId, {bool retired = false}) =>
      registry.releaseBufferGuard(guardId, retired: retired);
}

class const EditorBufferGuardScope({
  required final Set<String> tabIds,
  required final Set<String> workspacePaths,
});

class const EditorBufferGuardBlocker({
  required final String tabId,
  required final String path,
  required final String reason,
});

extension EditorBufferGuards on EditorSessionRegistry {
  /// Freeze first and then inspect, so a clean acknowledgement cannot race a
  /// new keystroke or save in this client. The runtime releases the guard.
  List<EditorBufferGuardBlocker> acquireBufferGuard(
    String id,
    EditorBufferGuardScope scope,
  ) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'A buffer guard ID is required');
    }
    final previous = _bufferGuards[id];
    if (previous != null &&
        (!setEquals(previous.tabIds, scope.tabIds) ||
            !setEquals(previous.workspacePaths, scope.workspacePaths))) {
      throw StateError('The scope of an active buffer guard cannot change.');
    }
    _bufferGuards[id] = EditorBufferGuardScope(
      tabIds: Set.unmodifiable(scope.tabIds),
      workspacePaths: Set.unmodifiable(scope.workspacePaths),
    );
    final blockers = <EditorBufferGuardBlocker>[];
    for (final tabId in {..._documents.keys, ..._sessions.keys}) {
      if (!_scopeContains(scope, tabId)) continue;
      final document = _documents[tabId];
      final saving =
          _pendingSaveTabs.contains(tabId) ||
          (_sessions[tabId]?.isSaving?.call() ?? false);
      if (saving || isDirty(tabId)) {
        blockers.add(
          EditorBufferGuardBlocker(
            tabId: tabId,
            path: document?.relativePath ?? tabId,
            reason: saving
                ? 'A file save is still in progress.'
                : 'The editor has unsaved changes.',
          ),
        );
      }
    }
    _notifyBufferGuardsChanged();
    return blockers;
  }

  bool isBufferGuarded(String tabId) =>
      _retiredBufferTabs.contains(tabId) ||
      _bufferGuards.values.any((scope) => _scopeContains(scope, tabId));

  void releaseBufferGuard(String id, {bool retired = false}) {
    final scope = _bufferGuards.remove(id);
    if (scope != null) {
      if (retired) {
        _retiredBufferTabs.addAll(
          scope.tabIds.where(
            (id) => _documents.containsKey(id) || _sessions.containsKey(id),
          ),
        );
      }
      _notifyBufferGuardsChanged();
    }
  }

  bool _scopeContains(EditorBufferGuardScope scope, String tabId) =>
      scope.tabIds.contains(tabId) ||
      scope.workspacePaths.contains(_documents[tabId]?.workspacePath);

  void requireBufferWritable(String tabId) {
    if (isBufferGuarded(tabId)) {
      throw StateError(
        'This editor is temporarily locked while Alera verifies a workspace operation.',
      );
    }
  }

  void _beginGuardedSave(String tabId) {
    requireBufferWritable(tabId);
    if (!_pendingSaveTabs.add(tabId)) {
      throw StateError('A save for this editor is already in progress.');
    }
  }
}
