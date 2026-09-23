import 'workbench_layout.dart';
import 'workspace_tab_record.dart';

WorkbenchLayout mergeWorkspaceTransferLayout({
  required String sourceId,
  required String destinationId,
  required List<WorkspaceTabRecord> sourceTabs,
  required List<WorkspaceTabRecord> destinationTabs,
  WorkbenchLayout? source,
  WorkbenchLayout? destination,
}) {
  final movedIds = sourceTabs.map((tab) => tab.id).toSet();
  final existing = destinationTabs
      .where((tab) => !movedIds.contains(tab.id))
      .toList();
  final from =
      (source ??
              WorkbenchLayout.single(
                workspaceId: sourceId,
                tabIds: sourceTabs.map((tab) => tab.id).toList(),
              ))
          .sanitize(sourceTabs);
  if (existing.isEmpty) return from.copyWith(workspaceId: destinationId);
  final to =
      (destination ??
              WorkbenchLayout.single(
                workspaceId: destinationId,
                tabIds: existing.map((tab) => tab.id).toList(),
              ))
          .sanitize(existing);
  if (sourceTabs.isEmpty) return to;
  final used = {...to.groups.keys, ...from.groups.keys};
  final names = <String, String>{};
  final groups = {...to.groups};
  for (final entry in from.groups.entries) {
    var id = entry.key;
    var suffix = 1;
    while (to.groups.containsKey(entry.key) && used.contains(id)) {
      id = '${entry.key}/handoff/${suffix++}';
    }
    used.add(id);
    names[entry.key] = id;
    groups[id] = entry.value.copyWith(id: id);
  }
  WorkbenchLayoutNode remap(WorkbenchLayoutNode node) => node.isLeaf
      ? WorkbenchLayoutNode.leaf(names[node.groupId]!)
      : WorkbenchLayoutNode.split(
          axis: node.axis!,
          first: remap(node.first!),
          second: remap(node.second!),
          ratio: node.ratio!,
        );
  return WorkbenchLayout(
    workspaceId: destinationId,
    root: WorkbenchLayoutNode.split(
      axis: .horizontal,
      first: remap(from.root),
      second: to.root,
      ratio: 0.5,
    ),
    groups: groups,
    activeGroupId: names[from.activeGroupId]!,
  );
}
