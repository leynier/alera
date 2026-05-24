import 'package:alera/src/features/workbench/domain/workbench_tab_record.dart';

const double workbenchMinSplitRatio = 0.15;
const double workbenchMaxSplitRatio = 0.85;

enum WorkbenchSplitAxis {
  horizontal('horizontal'),
  vertical('vertical');

  const WorkbenchSplitAxis(this.key);

  final String key;

  static WorkbenchSplitAxis fromJson(Object? value) {
    if (value is! String) {
      throw StateError('Workbench layout node missing split axis');
    }
    for (final axis in WorkbenchSplitAxis.values) {
      if (axis.key == value) {
        return axis;
      }
    }
    throw StateError('Workbench layout node has unknown split axis "$value"');
  }
}

enum WorkbenchDropZone { center, left, right, up, down }

class WorkbenchPaneGroup {
  WorkbenchPaneGroup({
    required this.id,
    required List<String> tabIds,
    required this.activeTabId,
  }) : tabIds = List<String>.unmodifiable(tabIds);

  final String id;
  final List<String> tabIds;
  final String? activeTabId;

  WorkbenchPaneGroup copyWith({
    List<String>? tabIds,
    String? activeTabId,
    bool clearActiveTabId = false,
  }) {
    return WorkbenchPaneGroup(
      id: id,
      tabIds: tabIds ?? this.tabIds,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'tabIds': tabIds,
      'activeTabId': activeTabId,
    };
  }

  factory WorkbenchPaneGroup.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw StateError('Workbench pane group missing id');
    }
    final tabIds = json['tabIds'];
    if (tabIds is! List) {
      throw StateError('Workbench pane group missing tabIds');
    }
    final activeTabId = json['activeTabId'];
    if (activeTabId != null && activeTabId is! String) {
      throw StateError('Workbench pane group has invalid activeTabId');
    }
    return WorkbenchPaneGroup(
      id: id,
      tabIds: tabIds.whereType<String>().toList(growable: false),
      activeTabId: activeTabId as String?,
    );
  }
}

class WorkbenchLayoutNode {
  const WorkbenchLayoutNode.leaf(this.groupId)
    : axis = null,
      first = null,
      second = null,
      ratio = null;

  const WorkbenchLayoutNode.split({
    required this.axis,
    required this.first,
    required this.second,
    required double ratio,
  }) : groupId = null,
       ratio = ratio < workbenchMinSplitRatio
           ? workbenchMinSplitRatio
           : (ratio > workbenchMaxSplitRatio ? workbenchMaxSplitRatio : ratio);

  final String? groupId;
  final WorkbenchSplitAxis? axis;
  final WorkbenchLayoutNode? first;
  final WorkbenchLayoutNode? second;
  final double? ratio;

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

  Map<String, Object?> toJson() {
    final groupId = this.groupId;
    if (groupId != null) {
      return <String, Object?>{'type': 'leaf', 'groupId': groupId};
    }
    return <String, Object?>{
      'type': 'split',
      'axis': axis!.key,
      'first': first!.toJson(),
      'second': second!.toJson(),
      'ratio': ratio,
    };
  }

  factory WorkbenchLayoutNode.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type == 'leaf') {
      final groupId = json['groupId'];
      if (groupId is! String || groupId.isEmpty) {
        throw StateError('Workbench layout leaf missing groupId');
      }
      return WorkbenchLayoutNode.leaf(groupId);
    }
    if (type == 'split') {
      final first = json['first'];
      final second = json['second'];
      final ratio = json['ratio'];
      if (first is! Map<String, Object?> || second is! Map<String, Object?>) {
        throw StateError('Workbench layout split missing children');
      }
      return WorkbenchLayoutNode.split(
        axis: WorkbenchSplitAxis.fromJson(json['axis']),
        first: WorkbenchLayoutNode.fromJson(first),
        second: WorkbenchLayoutNode.fromJson(second),
        ratio: ratio is num ? ratio.toDouble() : 0.5,
      );
    }
    throw StateError('Workbench layout node has unknown type "$type"');
  }
}

class WorkbenchLayout {
  WorkbenchLayout({
    required this.workspaceId,
    required this.root,
    required Map<String, WorkbenchPaneGroup> groups,
    required this.activeGroupId,
  }) : groups = Map<String, WorkbenchPaneGroup>.unmodifiable(groups);

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

  WorkbenchLayout sanitize(List<WorkbenchTabRecord> tabs) {
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
    return _copyWith(
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
    return _copyWith(
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
    return _copyWith(
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
    return _copyWith(root: root.updateSplitRatio(path, ratio));
  }

  WorkbenchLayout _copyWith({
    WorkbenchLayoutNode? root,
    Map<String, WorkbenchPaneGroup>? groups,
    String? activeGroupId,
  }) {
    return WorkbenchLayout(
      workspaceId: workspaceId,
      root: root ?? this.root,
      groups: groups ?? this.groups,
      activeGroupId: activeGroupId ?? this.activeGroupId,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'root': root.toJson(),
      'groups': <String, Object?>{
        for (final entry in groups.entries) entry.key: entry.value.toJson(),
      },
      'activeGroupId': activeGroupId,
    };
  }

  factory WorkbenchLayout.fromJson(Map<String, Object?> json) {
    final workspaceId = json['workspaceId'];
    final root = json['root'];
    final groups = json['groups'];
    final activeGroupId = json['activeGroupId'];
    if (workspaceId is! String || workspaceId.isEmpty) {
      throw StateError('Workbench layout missing workspaceId');
    }
    if (root is! Map<String, Object?>) {
      throw StateError('Workbench layout missing root');
    }
    if (groups is! Map) {
      throw StateError('Workbench layout missing groups');
    }
    if (activeGroupId is! String || activeGroupId.isEmpty) {
      throw StateError('Workbench layout missing activeGroupId');
    }
    return WorkbenchLayout(
      workspaceId: workspaceId,
      root: WorkbenchLayoutNode.fromJson(root),
      groups: <String, WorkbenchPaneGroup>{
        for (final entry in groups.entries)
          if (entry.key is String && entry.value is Map<String, Object?>)
            entry.key as String: WorkbenchPaneGroup.fromJson(
              entry.value as Map<String, Object?>,
            ),
      },
      activeGroupId: activeGroupId,
    );
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
