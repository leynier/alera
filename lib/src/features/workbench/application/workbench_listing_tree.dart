import 'package:alera/src/features/workbench/domain/workspace.dart';

/// One workspace positioned in the sidebar tree.
class WorkspaceTreeEntry {
  const WorkspaceTreeEntry({
    required this.workspace,
    required this.depth,
    required this.hasVisibleChildren,
    required this.childrenCollapsed,
  });

  final Workspace workspace;

  /// Nesting depth relative to the sibling group root (0 = root level).
  final int depth;

  /// Whether this workspace has children rendered (or collapsed) beneath it in
  /// the current group.
  final bool hasVisibleChildren;

  /// Whether this workspace's children are currently hidden by the user.
  final bool childrenCollapsed;
}

/// Deeper nesting reuses the max indent so rows stay readable in a narrow
/// sidebar.
const int maxWorkspaceTreeDepth = 4;

/// Orders one sibling group's already-filtered, already-sorted workspaces into
/// a depth-first tree. A workspace whose parent is not part of [entries]
/// (filtered out, in another group, or absent) is promoted to the root level,
/// so filters never hide a child.
List<WorkspaceTreeEntry> buildWorkspaceTree({
  required List<Workspace> entries,
  required Set<String> collapsedParentIds,
}) {
  final ids = <String>{for (final workspace in entries) workspace.id};
  final childrenOf = <String, List<Workspace>>{};
  final roots = <Workspace>[];
  for (final workspace in entries) {
    final parentId = workspace.parentWorkspaceId;
    if (parentId != null &&
        parentId != workspace.id &&
        ids.contains(parentId)) {
      childrenOf.putIfAbsent(parentId, () => <Workspace>[]).add(workspace);
    } else {
      roots.add(workspace);
    }
  }

  final out = <WorkspaceTreeEntry>[];
  // Guards against stale relation cycles so the walk always terminates.
  final visited = <String>{};

  void markSubtreeVisited(Workspace workspace) {
    if (!visited.add(workspace.id)) {
      return;
    }
    for (final child in childrenOf[workspace.id] ?? const <Workspace>[]) {
      markSubtreeVisited(child);
    }
  }

  void visit(Workspace workspace, int depth) {
    if (!visited.add(workspace.id)) {
      return;
    }
    final children = childrenOf[workspace.id] ?? const <Workspace>[];
    final collapsed = collapsedParentIds.contains(workspace.id);
    out.add(
      WorkspaceTreeEntry(
        workspace: workspace,
        depth: depth,
        hasVisibleChildren: children.isNotEmpty,
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
