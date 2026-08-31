/// A selected project/workspace pair kept by the workbench for this session.
class const WorktreeNavigationTarget({
  required final String projectId,
  required final String workspaceId,
}) {
  @override
  bool operator ==(Object other) {
    return other is WorktreeNavigationTarget &&
        other.projectId == projectId &&
        other.workspaceId == workspaceId;
  }

  @override
  int get hashCode => Object.hash(projectId, workspaceId);

  @override
  String toString() => 'WorktreeNavigationTarget($projectId, $workspaceId)';
}

/// In-memory back/forward history for selected worktrees.
///
/// The current target is kept separately from both stacks so recording a new
/// target after going back can discard the forward branch without affecting
/// the previous entries.
class WorktreeNavigationHistory {
  final List<WorktreeNavigationTarget> _back = <WorktreeNavigationTarget>[];
  final List<WorktreeNavigationTarget> _forward = <WorktreeNavigationTarget>[];
  WorktreeNavigationTarget? _current;

  bool get canGoBack => _back.isNotEmpty;

  bool get canGoForward => _forward.isNotEmpty;

  /// Records [target], suppressing consecutive duplicates and truncating the
  /// forward branch when the user starts a new navigation path.
  bool record(WorktreeNavigationTarget target) {
    if (_current == target) {
      return false;
    }
    if (_current case final current?) {
      _back.add(current);
    }
    _forward.clear();
    _current = target;
    return true;
  }

  /// Removes targets that are no longer present in the workbench.
  void prune(bool Function(WorktreeNavigationTarget target) isValid) {
    _back.removeWhere((target) => !isValid(target));
    _forward.removeWhere((target) => !isValid(target));
    if (_current case final current? when !isValid(current)) {
      _current = null;
    }
  }

  /// Returns the next valid back target without moving the cursor.
  WorktreeNavigationTarget? peekBack({
    required bool Function(WorktreeNavigationTarget target) isValid,
  }) {
    prune(isValid);
    if (_back.isEmpty) {
      return null;
    }
    return _back.last;
  }

  /// Returns the next valid forward target without moving the cursor.
  WorktreeNavigationTarget? peekForward({
    required bool Function(WorktreeNavigationTarget target) isValid,
  }) {
    prune(isValid);
    if (_forward.isEmpty) {
      return null;
    }
    return _forward.last;
  }

  /// Commits a previously peeked back target after its selection succeeds.
  void commitBack(WorktreeNavigationTarget target) {
    if (_back.isEmpty || _back.last != target) {
      throw StateError('Back target is no longer current.');
    }
    _back.removeLast();
    if (_current case final current?) {
      _forward.add(current);
    }
    _current = target;
  }

  /// Commits a previously peeked forward target after its selection succeeds.
  void commitForward(WorktreeNavigationTarget target) {
    if (_forward.isEmpty || _forward.last != target) {
      throw StateError('Forward target is no longer current.');
    }
    _forward.removeLast();
    if (_current case final current?) {
      _back.add(current);
    }
    _current = target;
  }
}
