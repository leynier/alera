import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'workspace_panel.mapper.dart';

enum WorkspacePanelTree { main, right }

/// Tool keys belong to desktop preferences, never to runtime tab records.
@MappableEnum()
enum WorkspaceTool {
  explorer,
  search,
  sourceControl,
  pullRequest;

  String get key => 'tool:$name';
  String get label => switch (this) {
    explorer => 'Explorer',
    search => 'Search',
    sourceControl => 'Source Control',
    pullRequest => 'Pull Request',
  };

  static WorkspaceTool? forKey(String? key) =>
      values.where((tool) => tool.key == key).firstOrNull;

  static List<WorkspaceTool> uniqueInOrder(Iterable<WorkspaceTool> tools) {
    final seen = <WorkspaceTool>{};
    return <WorkspaceTool>[
      for (final tool in tools)
        if (seen.add(tool)) tool,
    ];
  }

  static List<WorkspaceTool> settingsOrder(Iterable<WorkspaceTool> selected) {
    final enabled = uniqueInOrder(selected);
    return <WorkspaceTool>[
      ...enabled,
      for (final tool in values)
        if (!enabled.contains(tool)) tool,
    ];
  }

  static List<WorkspaceTool> selectedFromOrder({
    required Iterable<WorkspaceTool> order,
    required Iterable<WorkspaceTool> selected,
  }) {
    final enabled = selected.toSet();
    return <WorkspaceTool>[
      for (final tool in uniqueInOrder(order))
        if (enabled.contains(tool)) tool,
    ];
  }
}

bool isPrimaryTerminalCandidate(WorkspaceTabRecord tab) =>
    tab.kind == WorkspaceTabKind.terminal &&
    !tab.autoCloseOnSuccess &&
    !tab.initialCommandOnce &&
    tab.title != 'Setup';

List<String> workspacePanelLayoutKeys(WorkbenchLayout layout) => <String>[
  for (final groupId in layout.paneGroupIds)
    ...layout.groups[groupId]?.tabIds ?? const <String>[],
];

@MappableClass()
class const WorkspacePanel({
  this.primaryTabId,
  this.tabKeys = const <String>[],
  this.activeKey,
  this.focusedKey,
  this.paneLayout,
  this.mainLayout,
}) with WorkspacePanelMappable {
  final String? primaryTabId;
  final List<String> tabKeys;
  final String? activeKey;
  final String? focusedKey;
  final WorkbenchLayout? paneLayout;
  final WorkbenchLayout? mainLayout;

  static String tabKey(String tabId) => 'tab:$tabId';
  static String? tabId(String? key) =>
      key != null && key.startsWith('tab:') ? key.substring(4) : null;

  static WorkspacePanel fromNewWorkspaceTools(Iterable<WorkspaceTool> tools) {
    return const WorkspacePanel().openToolsInOrder(tools);
  }

  WorkspacePanel openToolsInOrder(Iterable<WorkspaceTool> tools) {
    final unique = WorkspaceTool.uniqueInOrder(tools);
    if (unique.isEmpty) {
      return this;
    }
    var panel = this;
    for (final tool in unique) {
      panel = panel.select(tool.key);
    }
    return panel.select(unique.first.key);
  }

  static const String fallbackLayoutWorkspaceId = 'workspace-panel';
  static const String mainLayoutGroupSuffix = 'workspace-main';

  List<String> get mainKeys => mainLayout == null
      ? const <String>[]
      : workspacePanelLayoutKeys(mainLayout!);

  bool get showsMainChrome => mainKeys.length > 1;

  Set<String> get occupiedKeys => <String>{...mainKeys, ...tabKeys};

  WorkbenchLayout ensuredLayout([String? workspaceId]) {
    return _ensured(paneLayout, tabKeys, activeKey, workspaceId);
  }

  WorkbenchLayout ensuredMainLayout([String? workspaceId]) {
    final seed = primaryTabId == null
        ? const <String>[]
        : <String>[tabKey(primaryTabId!)];
    final resolved = workspaceId ?? fallbackLayoutWorkspaceId;
    return _ensured(
      mainLayout,
      seed,
      seed.firstOrNull,
      workspaceId,
      defaultGroupId: '$resolved/$mainLayoutGroupSuffix',
    );
  }

  WorkbenchLayout _ensured(
    WorkbenchLayout? existing,
    List<String> keys,
    String? active,
    String? workspaceId, {
    String? defaultGroupId,
  }) {
    if (existing != null) {
      if (workspaceId == null || existing.workspaceId == workspaceId) {
        return existing;
      }
      return WorkbenchLayout(
        workspaceId: workspaceId,
        root: existing.root,
        groups: existing.groups,
        activeGroupId: existing.activeGroupId,
      );
    }
    final layout = WorkbenchLayout.single(
      workspaceId: workspaceId ?? fallbackLayoutWorkspaceId,
      tabIds: keys,
      groupId: defaultGroupId,
    );
    final groupId = active == null ? null : layout.groupIdForTab(active);
    if (active == null || groupId == null) {
      return layout;
    }
    return layout.setActiveTab(groupId: groupId, tabId: active);
  }

  WorkbenchLayout _singleMainLayout(String workspaceId, List<String> keys) {
    return WorkbenchLayout.single(
      workspaceId: workspaceId,
      tabIds: keys,
      groupId: '$workspaceId/$mainLayoutGroupSuffix',
    );
  }

  WorkspacePanel applyPaneLayout(WorkbenchLayout layout) {
    final keys = workspacePanelLayoutKeys(layout);
    final active = keys.contains(layout.activeTabId)
        ? layout.activeTabId
        : keys.firstOrNull;
    return copyWith(paneLayout: layout, tabKeys: keys, activeKey: active);
  }

  WorkspacePanel applyMainLayout(WorkbenchLayout layout) {
    final keys = workspacePanelLayoutKeys(layout);
    final primary = keys.length == 1 ? tabId(keys.single) : null;
    return copyWith(mainLayout: layout, primaryTabId: primary);
  }

  WorkspacePanel reconcile(
    List<WorkspaceTabRecord> tabs, {
    String? preferredPrimaryId,
    String? workspaceId,
  }) {
    final candidates = tabs.where(isPrimaryTerminalCandidate).toList();
    final preferred =
        candidates.where((tab) => tab.id == primaryTabId).firstOrNull ??
        candidates.where((tab) => tab.id == preferredPrimaryId).firstOrNull ??
        candidates.firstOrNull;
    final validTabKeys = <String>{for (final tab in tabs) tabKey(tab.id)};
    var main = ensuredMainLayout(workspaceId ?? mainLayout?.workspaceId);
    var mainKeySet = workspacePanelLayoutKeys(main)
        .where(
          (key) =>
              WorkspaceTool.forKey(key) != null || validTabKeys.contains(key),
        )
        .toSet();
    main = main.sanitizeIds(mainKeySet);
    mainKeySet = workspacePanelLayoutKeys(main).toSet();
    if (mainKeySet.isEmpty && preferred != null) {
      main = _singleMainLayout(workspaceId ?? main.workspaceId, <String>[
        tabKey(preferred.id),
      ]);
      mainKeySet = <String>{tabKey(preferred.id)};
    }
    final availableRight = <String>{
      for (final key in validTabKeys)
        if (!mainKeySet.contains(key)) key,
    };
    final rightKeys = <String>{
      for (final key in tabKeys)
        if (!mainKeySet.contains(key) &&
            (WorkspaceTool.forKey(key) != null || availableRight.contains(key)))
          key,
      ...availableRight,
    };
    final currentRight = ensuredLayout(workspaceId ?? paneLayout?.workspaceId);
    final right = currentRight.sanitizeIds(
      rightKeys,
      orphanGroupId: currentRight.activeGroupId,
    );
    final rightList = workspacePanelLayoutKeys(right);
    final rightActive = rightList.contains(right.activeTabId)
        ? right.activeTabId
        : rightList.firstOrNull;
    final primary = mainKeySet.length == 1 ? tabId(mainKeySet.single) : null;
    final primaryKey = primary == null ? null : tabKey(primary);
    final focused =
        focusedKey == primaryKey ||
            mainKeySet.contains(focusedKey) ||
            rightKeys.contains(focusedKey)
        ? focusedKey
        : primaryKey ?? rightActive;
    var next = applyMainLayout(main)
        .applyPaneLayout(right)
        .copyWith(focusedKey: focused);
    if (rightActive != null &&
        next.paneLayout?.groupIdForTab(rightActive) != null) {
      next = next
          .applyPaneLayout(
            next.paneLayout!.setActiveTab(
              groupId: next.paneLayout!.groupIdForTab(rightActive)!,
              tabId: rightActive,
            ),
          )
          .copyWith(focusedKey: focused);
    }
    return next;
  }

  WorkspacePanelTree? treeForKey(String key) {
    if (ensuredMainLayout().groupIdForTab(key) != null) {
      return WorkspacePanelTree.main;
    }
    if (ensuredLayout().groupIdForTab(key) != null) {
      return WorkspacePanelTree.right;
    }
    return null;
  }

  WorkspacePanelTree? treeForGroup(String groupId) {
    if (ensuredMainLayout().groups.containsKey(groupId)) {
      return WorkspacePanelTree.main;
    }
    if (ensuredLayout().groups.containsKey(groupId)) {
      return WorkspacePanelTree.right;
    }
    return null;
  }

  WorkspacePanel select(String key, {String? groupId}) {
    if (key == tabKey(primaryTabId ?? '')) {
      return copyWith(focusedKey: key);
    }
    final main = ensuredMainLayout();
    final mainGroup = main.groupIdForTab(key);
    if (mainGroup != null) {
      return applyMainLayout(main.setActiveTab(groupId: mainGroup, tabId: key))
          .copyWith(focusedKey: key);
    }
    final layout = ensuredLayout();
    final existingGroupId = layout.groupIdForTab(key);
    if (existingGroupId != null) {
      return applyPaneLayout(
        layout.setActiveTab(groupId: existingGroupId, tabId: key),
      ).copyWith(focusedKey: key);
    }
    if (groupId != null && main.groups.containsKey(groupId)) {
      return applyMainLayout(main.addTabToGroup(groupId: groupId, tabId: key))
          .copyWith(focusedKey: key);
    }
    final resolvedGroupId =
        groupId != null && layout.groups.containsKey(groupId)
        ? groupId
        : layout.activeGroupId;
    return applyPaneLayout(
      layout.addTabToGroup(groupId: resolvedGroupId, tabId: key),
    ).copyWith(focusedKey: key);
  }

  WorkspacePanel closeTool(WorkspaceTool tool) {
    return closeKey(tool.key);
  }

  WorkspacePanel closeKey(String key) {
    final main = mainLayout ?? ensuredMainLayout();
    if (main.groupIdForTab(key) != null) {
      final next = applyMainLayout(main.removeTab(key));
      return next.copyWith(
        focusedKey: focusedKey == key
            ? (next.ensuredMainLayout().activeTabId ??
                  next.mainKeys.firstOrNull ??
                  next.activeKey)
            : focusedKey,
      );
    }
    final layout = paneLayout ?? ensuredLayout();
    if (layout.groupIdForTab(key) == null && !tabKeys.contains(key)) {
      return this;
    }
    final next = applyPaneLayout(layout.removeTab(key));
    final active = next.activeKey;
    final mainFallback =
        next.ensuredMainLayout().activeTabId ?? next.mainKeys.firstOrNull;
    return next.copyWith(
      focusedKey: focusedKey == key
          ? active ?? mainFallback
          : focusedKey,
    );
  }

  WorkspacePanel moveKey({
    required String key,
    required WorkspacePanelTree target,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    required String newGroupId,
    int? index,
  }) {
    var sourceMain = ensuredMainLayout();
    var sourceRight = ensuredLayout();
    final inMain = sourceMain.groupIdForTab(key) != null;
    if (inMain) {
      sourceMain = sourceMain.removeTab(key);
    } else {
      sourceRight = sourceRight.removeTab(key);
    }
    final dest = target == WorkspacePanelTree.main ? sourceMain : sourceRight;
    final resolvedTarget = dest.groups.containsKey(targetGroupId)
        ? targetGroupId
        : dest.activeGroupId;
    final placed = _placeKey(
      dest,
      key: key,
      targetGroupId: resolvedTarget,
      zone: zone,
      newGroupId: newGroupId,
      index: index,
    );
    final next = target == WorkspacePanelTree.main
        ? applyMainLayout(placed).applyPaneLayout(sourceRight)
        : applyMainLayout(sourceMain).applyPaneLayout(placed);
    return next.copyWith(focusedKey: key);
  }

  WorkbenchLayout _placeKey(
    WorkbenchLayout dest, {
    required String key,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    required String newGroupId,
    int? index,
  }) {
    if (zone == WorkbenchDropZone.center) {
      return dest.addTabToGroup(
        groupId: targetGroupId,
        tabId: key,
        index: index,
      );
    }
    return dest.splitWithGroup(
      targetGroupId: targetGroupId,
      zone: zone,
      newGroup: WorkbenchPaneGroup(
        id: newGroupId,
        tabIds: <String>[key],
        activeTabId: key,
      ),
    );
  }
}
