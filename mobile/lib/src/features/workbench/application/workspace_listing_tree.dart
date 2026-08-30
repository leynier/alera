import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

// Adapted from the desktop tree builder at
// lib/src/features/workbench/application/workbench_listing_tree.dart,
// retargeted to the mobile WorkspaceSummary model. Keep the algorithms in
// sync when the desktop version changes.

/// One workspace positioned in the sidebar tree.
class const WorkspaceTreeEntry({
  required final WorkspaceSummary workspace,
  required this.depth,
  required this.visibleChildCount,
  required this.childrenCollapsed,
}) {
  /// Nesting depth relative to the sibling group root (0 = root level).
  final int depth;

  /// How many children this workspace has in the current filtered/sibling
  /// group (including when those children are collapsed and not rendered).
  final int visibleChildCount;

  /// Whether this workspace has children rendered (or collapsed) beneath it in
  /// the current group.
  bool get hasVisibleChildren => visibleChildCount > 0;

  /// Whether this workspace's children are currently hidden by the user.
  final bool childrenCollapsed;
}

/// Deeper nesting reuses the max indent so rows stay readable on a phone.
const int maxWorkspaceTreeDepth = 4;

/// Orders one sibling group's already-filtered, already-sorted workspaces into
/// a depth-first tree. A workspace whose parent is not part of [entries]
/// (filtered out, in another group, or absent) is promoted to the root level,
/// so filters never hide a child.
List<WorkspaceTreeEntry> buildWorkspaceTree({
  required List<WorkspaceSummary> entries,
  required Set<String> collapsedParentIds,
}) {
  final ids = <String>{for (final workspace in entries) workspace.id};
  final childrenOf = <String, List<WorkspaceSummary>>{};
  final roots = <WorkspaceSummary>[];
  for (final workspace in entries) {
    final parentId = workspace.parentWorkspaceId;
    if (parentId != null &&
        parentId != workspace.id &&
        ids.contains(parentId)) {
      childrenOf
          .putIfAbsent(parentId, () => <WorkspaceSummary>[])
          .add(workspace);
    } else {
      roots.add(workspace);
    }
  }

  final out = <WorkspaceTreeEntry>[];
  // Guards against stale relation cycles so the walk always terminates.
  final visited = <String>{};

  void markSubtreeVisited(WorkspaceSummary workspace) {
    if (!visited.add(workspace.id)) {
      return;
    }
    for (final child
        in childrenOf[workspace.id] ?? const <WorkspaceSummary>[]) {
      markSubtreeVisited(child);
    }
  }

  void visit(WorkspaceSummary workspace, int depth) {
    if (!visited.add(workspace.id)) {
      return;
    }
    final children = childrenOf[workspace.id] ?? const <WorkspaceSummary>[];
    final collapsed = collapsedParentIds.contains(workspace.id);
    out.add(
      WorkspaceTreeEntry(
        workspace: workspace,
        depth: depth,
        visibleChildCount: children.length,
        childrenCollapsed: collapsed,
      ),
    );
    if (collapsed) {
      for (final child in children) {
        markSubtreeVisited(child);
      }
      return;
    }
    final childDepth = depth >= maxWorkspaceTreeDepth
        ? maxWorkspaceTreeDepth
        : depth + 1;
    for (final child in children) {
      visit(child, childDepth);
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  // A cycle among non-root workspaces leaves them unvisited; append them at
  // the root level rather than dropping them.
  for (final workspace in entries) {
    if (!visited.contains(workspace.id)) {
      visit(workspace, 0);
    }
  }
  return out;
}

/// Ids of every descendant of [workspaceId] given the current workspace set.
/// Used to keep parent selection acyclic on the phone.
Set<String> workspaceDescendantIds(
  List<WorkspaceSummary> workspaces,
  String workspaceId,
) {
  final childrenOf = <String, List<String>>{};
  for (final workspace in workspaces) {
    final parentId = workspace.parentWorkspaceId;
    if (parentId != null && parentId != workspace.id) {
      childrenOf.putIfAbsent(parentId, () => <String>[]).add(workspace.id);
    }
  }
  final out = <String>{};
  void visit(String id) {
    for (final childId in childrenOf[id] ?? const <String>[]) {
      if (out.add(childId)) {
        visit(childId);
      }
    }
  }

  visit(workspaceId);
  return out;
}
