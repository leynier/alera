import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// Which tab each workspace was looking at, most recent first.
///
/// Session-only on purpose: focus order is ephemeral, and persisting it would
/// restore a focus the user did not leave behind. Each workspace keeps a
/// bounded slice so a long-lived session cannot grow it without limit.
class WorkspaceTabFocusHistory({this.limit = 50}) {
  /// Entries kept per workspace. Far more than anyone tabs through, and small
  /// enough that the list stays cheap to scan.
  final int limit;

  final Map<String, List<String>> _byWorkspace = <String, List<String>>{};

  void record(String workspaceId, String tabId) {
    final history = _byWorkspace.putIfAbsent(workspaceId, () => <String>[]);
    history.remove(tabId);
    history.insert(0, tabId);
    if (history.length > limit) {
      history.removeRange(limit, history.length);
    }
  }

  /// The most recently focused tab that is still open, or null when none of
  /// the remembered tabs survived.
  String? mostRecentOpen(String workspaceId, Set<String> openTabIds) {
    final history = _byWorkspace[workspaceId];
    if (history == null) {
      return null;
    }
    history.removeWhere((tabId) => !openTabIds.contains(tabId));
    if (history.isEmpty) {
      _byWorkspace.remove(workspaceId);
      return null;
    }
    return history.first;
  }

  /// Drops a workspace's history. Called when the workspace or its project
  /// goes away, so a removed workspace cannot leak focus into the id space of
  /// a later one.
  void forget(String workspaceId) => _byWorkspace.remove(workspaceId);
}

/// [layout] with focus moved to the most recently used tab that is still open.
///
/// Returns [layout] unchanged when the closed tabs did not include the active
/// one, or when nothing in the history survived the close: the layout's own
/// sanitize already picked something reasonable in that case.
WorkbenchLayout refocusMostRecentlyUsedTab({
  required WorkbenchLayout layout,
  required WorkspaceTabFocusHistory history,
  required String workspaceId,
  required List<WorkspaceTabRecord> remaining,
}) {
  final openTabIds = <String>{for (final tab in remaining) tab.id};
  final tabId = history.mostRecentOpen(workspaceId, openTabIds);
  final groupId = tabId == null ? null : layout.groupIdForTab(tabId);
  if (tabId == null || groupId == null) {
    return layout;
  }
  return layout.setActiveTab(groupId: groupId, tabId: tabId);
}
