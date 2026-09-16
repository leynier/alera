/// In-memory Explorer UI session for one workspace.
///
/// Stores only the expanded folder relative paths and the tree scroll offset.
/// Directory listings and node objects stay out of this snapshot so switching
/// context tabs does not keep the tree alive in RAM.
class const WorkspaceExplorerSession({
  required final Set<String> expandedRelativePaths,
  final double scrollOffset = 0,
}) {
  bool get isEmpty => expandedRelativePaths.isEmpty && scrollOffset.abs() < 1;
}

/// Compact Explorer session cache keyed by workspace id.
///
/// Mutations do not notify listeners. The Explorer widget reads and writes
/// this store around mount/unmount so expand/collapse and scrolling stay off
/// the Riverpod rebuild path.
class WorkspaceExplorerSessionStore {
  final Map<String, WorkspaceExplorerSession> _byWorkspaceId =
      <String, WorkspaceExplorerSession>{};
  Set<String>? _retainIds;

  WorkspaceExplorerSession? peek(String workspaceId) =>
      _byWorkspaceId[workspaceId];

  void save(String workspaceId, WorkspaceExplorerSession session) {
    if (_retainIds != null && !_retainIds!.contains(workspaceId)) {
      _byWorkspaceId.remove(workspaceId);
      return;
    }
    if (session.isEmpty) {
      _byWorkspaceId.remove(workspaceId);
      return;
    }
    _byWorkspaceId[workspaceId] = session;
  }

  /// Drops sessions for workspaces that are no longer selected and have no
  /// open tabs.
  void retain(Set<String> workspaceIds) {
    _retainIds = workspaceIds;
    if (_byWorkspaceId.isEmpty) {
      return;
    }
    _byWorkspaceId.removeWhere(
      (workspaceId, _) => !workspaceIds.contains(workspaceId),
    );
  }
}
