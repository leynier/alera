import 'package:alera/src/features/workbench/domain/workspace.dart';

/// Ids of every descendant of [workspaceId] given the current workspace set.
/// Used to pin or unpin a whole child tree from the sidebar.
Set<String> workspaceIdsDescendedFrom(
  Iterable<Workspace> workspaces,
  String workspaceId,
) {
  final childrenOf = <String, List<String>>{};
  for (final workspace in workspaces) {
    final parentId = workspace.parentWorkspaceId;
    if (parentId != null && parentId != workspace.id) {
      childrenOf.putIfAbsent(parentId, () => <String>[]).add(workspace.id);
    }
  }
  final descendants = <String>{};
  // Seed with the root so a stale parent cycle cannot re-enter it and treat
  // the clicked workspace as its own descendant.
  final visited = <String>{workspaceId};
  void visit(String id) {
    for (final childId in childrenOf[id] ?? const <String>[]) {
      if (!visited.add(childId)) {
        continue;
      }
      descendants.add(childId);
      visit(childId);
    }
  }

  visit(workspaceId);
  return descendants;
}
