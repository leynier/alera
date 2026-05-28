part of 'workbench_layout.dart';

extension WorkbenchLayoutMutations on WorkbenchLayout {
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
    final prunedRoot = _resolvedMergedRoot(
      root,
      nextGroups.keys.toSet(),
      siblingGroupId,
    );
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
