import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'workbench_layout.mapper.dart';

const double workbenchMinSplitRatio = 0.15;
const double workbenchMaxSplitRatio = 0.85;

@MappableEnum()
enum WorkbenchSplitAxis { horizontal, vertical }

enum WorkbenchDropZone { center, left, right, up, down }

@MappableClass()
class WorkbenchPaneGroup with WorkbenchPaneGroupMappable {
  WorkbenchPaneGroup({
    required this.id,
    required List<String> tabIds,
    required this.activeTabId,
  }) : tabIds = List<String>.unmodifiable(tabIds) {
    if (id.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'Workbench pane group id must not be empty.',
      );
    }
  }

  final String id;
  final List<String> tabIds;
  final String? activeTabId;

  factory WorkbenchPaneGroup.fromJson(Map<String, Object?> json) =>
      WorkbenchPaneGroupMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass(discriminatorKey: 'type')
abstract class WorkbenchLayoutNode with WorkbenchLayoutNodeMappable {
  const WorkbenchLayoutNode();

  factory WorkbenchLayoutNode.leaf(String groupId) = WorkbenchLeafLayoutNode;
  factory WorkbenchLayoutNode.split({
    required WorkbenchSplitAxis axis,
    required WorkbenchLayoutNode first,
    required WorkbenchLayoutNode second,
    required double ratio,
  }) = WorkbenchSplitLayoutNode;

  factory WorkbenchLayoutNode.fromJson(Map<String, Object?> json) =>
      WorkbenchLayoutNodeMapper.fromMap(Map<String, dynamic>.from(json));

  String? get groupId => null;
  WorkbenchSplitAxis? get axis => null;
  WorkbenchLayoutNode? get first => null;
  WorkbenchLayoutNode? get second => null;
  double? get ratio => null;

  bool get isLeaf => groupId != null;

  List<String> leafGroupIds() {
    final groupId = this.groupId;
    if (groupId != null) {
      return <String>[groupId];
    }
    return <String>[
      ...first?.leafGroupIds() ?? const <String>[],
      ...second?.leafGroupIds() ?? const <String>[],
    ];
  }

  bool containsGroup(String groupId) {
    if (this.groupId == groupId) {
      return true;
    }
    return (first?.containsGroup(groupId) ?? false) ||
        (second?.containsGroup(groupId) ?? false);
  }

  WorkbenchLayoutNode replaceLeaf(
    String targetGroupId,
    WorkbenchLayoutNode replacement,
  ) {
    final groupId = this.groupId;
    if (groupId != null) {
      return groupId == targetGroupId ? replacement : this;
    }
    return WorkbenchLayoutNode.split(
      axis: axis!,
      first: first!.replaceLeaf(targetGroupId, replacement),
      second: second!.replaceLeaf(targetGroupId, replacement),
      ratio: ratio!,
    );
  }

  WorkbenchLayoutNode? pruneGroups(Set<String> validGroupIds) {
    final groupId = this.groupId;
    if (groupId != null) {
      return validGroupIds.contains(groupId) ? this : null;
    }
    final prunedFirst = first!.pruneGroups(validGroupIds);
    final prunedSecond = second!.pruneGroups(validGroupIds);
    if (prunedFirst == null) {
      return prunedSecond;
    }
    if (prunedSecond == null) {
      return prunedFirst;
    }
    return WorkbenchLayoutNode.split(
      axis: axis!,
      first: prunedFirst,
      second: prunedSecond,
      ratio: ratio!,
    );
  }

  WorkbenchLayoutNode updateSplitRatio(List<int> path, double nextRatio) {
    if (path.isEmpty) {
      if (isLeaf) {
        return this;
      }
      return WorkbenchLayoutNode.split(
        axis: axis!,
        first: first!,
        second: second!,
        ratio: nextRatio,
      );
    }
    if (isLeaf) {
      return this;
    }
    final head = path.first;
    final tail = path.sublist(1);
    return WorkbenchLayoutNode.split(
      axis: axis!,
      first: head == 0 ? first!.updateSplitRatio(tail, nextRatio) : first!,
      second: head == 1 ? second!.updateSplitRatio(tail, nextRatio) : second!,
      ratio: ratio!,
    );
  }
}

@MappableClass(discriminatorValue: 'leaf')
class WorkbenchLeafLayoutNode extends WorkbenchLayoutNode
    with WorkbenchLeafLayoutNodeMappable {
  WorkbenchLeafLayoutNode(this.groupId) {
    if (groupId.isEmpty) {
      throw ArgumentError.value(
        groupId,
        'groupId',
        'Workbench layout leaf group id must not be empty.',
      );
    }
  }

  @override
  final String groupId;
}

@MappableClass(discriminatorValue: 'split')
class WorkbenchSplitLayoutNode extends WorkbenchLayoutNode
    with WorkbenchSplitLayoutNodeMappable {
  WorkbenchSplitLayoutNode({
    required this.axis,
    required this.first,
    required this.second,
    required double ratio,
  }) : ratio = _clampWorkbenchSplitRatio(ratio);

  @override
  final WorkbenchSplitAxis axis;

  @override
  final WorkbenchLayoutNode first;

  @override
  final WorkbenchLayoutNode second;

  @override
  final double ratio;
}

@MappableClass()
class WorkbenchLayout with WorkbenchLayoutMappable {
  WorkbenchLayout({
    required this.workspaceId,
    required this.root,
    required Map<String, WorkbenchPaneGroup> groups,
    required this.activeGroupId,
  }) : groups = Map<String, WorkbenchPaneGroup>.unmodifiable(groups) {
    if (workspaceId.isEmpty) {
      throw ArgumentError.value(
        workspaceId,
        'workspaceId',
        'Workbench layout workspace id must not be empty.',
      );
    }
    if (activeGroupId.isEmpty) {
      throw ArgumentError.value(
        activeGroupId,
        'activeGroupId',
        'Workbench layout active group id must not be empty.',
      );
    }
  }

  final String workspaceId;
  final WorkbenchLayoutNode root;
  final Map<String, WorkbenchPaneGroup> groups;
  final String activeGroupId;

  static String defaultGroupId(String workspaceId) => '$workspaceId/main';

  factory WorkbenchLayout.single({
    required String workspaceId,
    required List<String> tabIds,
    String? groupId,
  }) {
    final resolvedGroupId = groupId ?? defaultGroupId(workspaceId);
    return WorkbenchLayout(
      workspaceId: workspaceId,
      root: WorkbenchLayoutNode.leaf(resolvedGroupId),
      groups: <String, WorkbenchPaneGroup>{
        resolvedGroupId: WorkbenchPaneGroup(
          id: resolvedGroupId,
          tabIds: tabIds,
          activeTabId: tabIds.isEmpty ? null : tabIds.last,
        ),
      },
      activeGroupId: resolvedGroupId,
    );
  }

  factory WorkbenchLayout.fromJson(Map<String, Object?> json) =>
      WorkbenchLayoutMapper.fromMap(Map<String, dynamic>.from(json));

  WorkbenchPaneGroup? get activeGroup => groups[activeGroupId];

  String? get activeTabId => activeGroup?.activeTabId;

  List<String> get paneGroupIds => root.leafGroupIds();

  String? groupIdForTab(String tabId) {
    for (final group in groups.values) {
      if (group.tabIds.contains(tabId)) {
        return group.id;
      }
    }
    return null;
  }

  WorkbenchLayout sanitize(List<WorkspaceTabRecord> tabs) {
    final validTabIds = <String>{for (final tab in tabs) tab.id};
    final nextGroups = <String, WorkbenchPaneGroup>{};
    final assignedTabIds = <String>{};
    for (final entry in groups.entries) {
      final tabIds = <String>[
        for (final tabId in entry.value.tabIds)
          if (validTabIds.contains(tabId) && assignedTabIds.add(tabId)) tabId,
      ];
      if (tabIds.isEmpty) {
        continue;
      }
      final activeTabId = tabIds.contains(entry.value.activeTabId)
          ? entry.value.activeTabId
          : tabIds.first;
      nextGroups[entry.key] = entry.value.copyWith(
        tabIds: tabIds,
        activeTabId: activeTabId,
      );
    }
    final orphanTabIds = <String>[
      for (final tab in tabs)
        if (!assignedTabIds.contains(tab.id)) tab.id,
    ];
    if (nextGroups.isEmpty) {
      return WorkbenchLayout.single(
        workspaceId: workspaceId,
        tabIds: <String>[...orphanTabIds],
      );
    }
    final prunedRoot = root.pruneGroups(nextGroups.keys.toSet());
    if (prunedRoot == null) {
      return WorkbenchLayout.single(
        workspaceId: workspaceId,
        tabIds: <String>[
          for (final group in nextGroups.values) ...group.tabIds,
          ...orphanTabIds,
        ],
      );
    }
    final leafGroupIds = prunedRoot.leafGroupIds();
    final firstGroupId = leafGroupIds.first;
    if (orphanTabIds.isNotEmpty) {
      final group = nextGroups[firstGroupId]!;
      final tabIds = <String>[...group.tabIds, ...orphanTabIds];
      nextGroups[firstGroupId] = group.copyWith(
        tabIds: tabIds,
        activeTabId: group.activeTabId ?? tabIds.first,
      );
    }
    final activeGroupId = leafGroupIds.contains(this.activeGroupId)
        ? this.activeGroupId
        : firstGroupId;
    return WorkbenchLayout(
      workspaceId: workspaceId,
      root: prunedRoot,
      groups: <String, WorkbenchPaneGroup>{
        for (final groupId in leafGroupIds) groupId: nextGroups[groupId]!,
      },
      activeGroupId: activeGroupId,
    );
  }

  WorkbenchLayout setActiveTab({
    required String groupId,
    required String tabId,
  }) {
    final group = groups[groupId];
    if (group == null || !group.tabIds.contains(tabId)) {
      return this;
    }
    return copyWith(
      groups: <String, WorkbenchPaneGroup>{
        ...groups,
        groupId: group.copyWith(activeTabId: tabId),
      },
      activeGroupId: groupId,
    );
  }

  WorkbenchLayout addTabToGroup({
    required String groupId,
    required String tabId,
    int? index,
  }) {
    final group = groups[groupId];
    if (group == null) {
      return this;
    }
    final tabIds = <String>[...group.tabIds]..remove(tabId);
    final insertIndex = index == null
        ? tabIds.length
        : index.clamp(0, tabIds.length);
    tabIds.insert(insertIndex, tabId);
    return copyWith(
      groups: <String, WorkbenchPaneGroup>{
        ...groups,
        groupId: group.copyWith(tabIds: tabIds, activeTabId: tabId),
      },
      activeGroupId: groupId,
    );
  }

  WorkbenchLayout removeTab(String tabId) {
    final nextGroups = <String, WorkbenchPaneGroup>{};
    for (final entry in groups.entries) {
      final tabIds = <String>[...entry.value.tabIds]..remove(tabId);
      if (tabIds.isEmpty) {
        continue;
      }
      final activeTabId = entry.value.activeTabId == tabId
          ? tabIds.first
          : (tabIds.contains(entry.value.activeTabId)
                ? entry.value.activeTabId
                : tabIds.first);
      nextGroups[entry.key] = entry.value.copyWith(
        tabIds: tabIds,
        activeTabId: activeTabId,
      );
    }
    if (nextGroups.isEmpty) {
      return WorkbenchLayout.single(workspaceId: workspaceId, tabIds: const []);
    }
    final prunedRoot = root.pruneGroups(nextGroups.keys.toSet());
    if (prunedRoot == null) {
      final tabIds = <String>[
        for (final group in nextGroups.values) ...group.tabIds,
      ];
      return WorkbenchLayout.single(workspaceId: workspaceId, tabIds: tabIds);
    }
    final leafGroupIds = prunedRoot.leafGroupIds();
    final nextActiveGroupId = leafGroupIds.contains(activeGroupId)
        ? activeGroupId
        : leafGroupIds.first;
    return WorkbenchLayout(
      workspaceId: workspaceId,
      root: prunedRoot,
      groups: <String, WorkbenchPaneGroup>{
        for (final groupId in leafGroupIds) groupId: nextGroups[groupId]!,
      },
      activeGroupId: nextActiveGroupId,
    );
  }

  WorkbenchLayout splitWithGroup({
    required String targetGroupId,
    required WorkbenchDropZone zone,
    required WorkbenchPaneGroup newGroup,
  }) {
    final axis = _axisForZone(zone);
    if (axis == null || !root.containsGroup(targetGroupId)) {
      return this;
    }
    final targetLeaf = WorkbenchLayoutNode.leaf(targetGroupId);
    final newLeaf = WorkbenchLayoutNode.leaf(newGroup.id);
    final replacement =
        zone == WorkbenchDropZone.left || zone == WorkbenchDropZone.up
        ? WorkbenchLayoutNode.split(
            axis: axis,
            first: newLeaf,
            second: targetLeaf,
            ratio: 0.5,
          )
        : WorkbenchLayoutNode.split(
            axis: axis,
            first: targetLeaf,
            second: newLeaf,
            ratio: 0.5,
          );
    return copyWith(
      root: root.replaceLeaf(targetGroupId, replacement),
      groups: <String, WorkbenchPaneGroup>{...groups, newGroup.id: newGroup},
      activeGroupId: newGroup.id,
    );
  }

  WorkbenchLayout moveTab({
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    required String newGroupId,
    int? index,
  }) {
    final sourceGroupId = groupIdForTab(tabId);
    if (sourceGroupId == null) {
      return this;
    }
    if (zone == WorkbenchDropZone.center) {
      final withoutTab = removeTab(tabId);
      final resolvedTargetGroupId = withoutTab.groups.containsKey(targetGroupId)
          ? targetGroupId
          : withoutTab.activeGroupId;
      return withoutTab.addTabToGroup(
        groupId: resolvedTargetGroupId,
        tabId: tabId,
        index: index,
      );
    }
    final sourceGroup = groups[sourceGroupId]!;
    if (sourceGroupId == targetGroupId && sourceGroup.tabIds.length == 1) {
      return this;
    }
    final withoutTab = removeTab(tabId);
    final resolvedTargetGroupId = withoutTab.groups.containsKey(targetGroupId)
        ? targetGroupId
        : withoutTab.activeGroupId;
    return withoutTab.splitWithGroup(
      targetGroupId: resolvedTargetGroupId,
      zone: zone,
      newGroup: WorkbenchPaneGroup(
        id: newGroupId,
        tabIds: <String>[tabId],
        activeTabId: tabId,
      ),
    );
  }

  WorkbenchLayout mergeGroupIntoSibling(String groupId) {
    if (!groups.containsKey(groupId) || paneGroupIds.length <= 1) {
      return this;
    }
    final siblingGroupId = _firstSiblingGroupId(root, groupId);
    if (siblingGroupId == null) {
      return this;
    }
    final source = groups[groupId]!;
    final target = groups[siblingGroupId]!;
    final mergedTabIds = <String>[...target.tabIds, ...source.tabIds];
    final nextGroups = <String, WorkbenchPaneGroup>{...groups}
      ..remove(groupId)
      ..[siblingGroupId] = target.copyWith(
        tabIds: mergedTabIds,
        activeTabId: source.activeTabId ?? target.activeTabId,
      );
    final prunedRoot = root.pruneGroups(nextGroups.keys.toSet());
    if (prunedRoot == null) {
      return WorkbenchLayout.single(
        workspaceId: workspaceId,
        tabIds: mergedTabIds,
        groupId: siblingGroupId,
      );
    }
    return WorkbenchLayout(
      workspaceId: workspaceId,
      root: prunedRoot,
      groups: nextGroups,
      activeGroupId: siblingGroupId,
    );
  }

  WorkbenchLayout updateSplitRatio(List<int> path, double ratio) {
    return copyWith(root: root.updateSplitRatio(path, ratio));
  }
}

WorkbenchSplitAxis? _axisForZone(WorkbenchDropZone zone) {
  return switch (zone) {
    WorkbenchDropZone.left ||
    WorkbenchDropZone.right => WorkbenchSplitAxis.horizontal,
    WorkbenchDropZone.up ||
    WorkbenchDropZone.down => WorkbenchSplitAxis.vertical,
    WorkbenchDropZone.center => null,
  };
}

double _clampWorkbenchSplitRatio(double ratio) {
  if (ratio < workbenchMinSplitRatio) {
    return workbenchMinSplitRatio;
  }
  if (ratio > workbenchMaxSplitRatio) {
    return workbenchMaxSplitRatio;
  }
  return ratio;
}

String? _firstSiblingGroupId(WorkbenchLayoutNode node, String groupId) {
  if (node.isLeaf) {
    return null;
  }
  final first = node.first!;
  final second = node.second!;
  if (first.groupId == groupId) {
    final siblings = second.leafGroupIds();
    return siblings.isEmpty ? null : siblings.first;
  }
  if (second.groupId == groupId) {
    final siblings = first.leafGroupIds();
    return siblings.isEmpty ? null : siblings.first;
  }
  if (first.containsGroup(groupId)) {
    return _firstSiblingGroupId(first, groupId);
  }
  if (second.containsGroup(groupId)) {
    return _firstSiblingGroupId(second, groupId);
  }
  return null;
}
