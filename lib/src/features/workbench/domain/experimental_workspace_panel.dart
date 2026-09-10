import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'experimental_workspace_panel.mapper.dart';

@MappableEnum()
enum DesktopWorkspaceLayout { classic, experimental }

enum ExperimentalPanelTree { main, right }

/// Tool keys belong to desktop preferences, never to runtime tab records.
@MappableEnum()
enum ExperimentalWorkspaceTool {
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

  static ExperimentalWorkspaceTool? forKey(String? key) =>
      values.where((tool) => tool.key == key).firstOrNull;
}

bool isExperimentalPrimaryCandidate(WorkspaceTabRecord tab) =>
    tab.kind == WorkspaceTabKind.terminal &&
    !tab.autoCloseOnSuccess &&
    !tab.initialCommandOnce &&
    tab.title != 'Setup';

List<String> experimentalLayoutKeys(WorkbenchLayout layout) => <String>[
  for (final groupId in layout.paneGroupIds)
    ...layout.groups[groupId]?.tabIds ?? const <String>[],
];

@MappableClass()
class const ExperimentalWorkspacePanel({
  this.primaryTabId,
  this.tabKeys = const <String>[],
  this.activeKey,
  this.focusedKey,
  this.paneLayout,
  this.mainLayout,
}) with ExperimentalWorkspacePanelMappable {
  final String? primaryTabId;
  final List<String> tabKeys;
  final String? activeKey;
  final String? focusedKey;
  final WorkbenchLayout? paneLayout;
  final WorkbenchLayout? mainLayout;

  static String tabKey(String tabId) => 'tab:$tabId';
  static String? tabId(String? key) =>
      key != null && key.startsWith('tab:') ? key.substring(4) : null;

  static const String fallbackLayoutWorkspaceId = 'experimental-panel';
  static const String mainLayoutGroupSuffix = 'experimental-main';

  List<String> get mainKeys => mainLayout == null
      ? const <String>[]
      : experimentalLayoutKeys(mainLayout!);

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

  ExperimentalWorkspacePanel applyPaneLayout(WorkbenchLayout layout) {
    final keys = experimentalLayoutKeys(layout);
    final active = keys.contains(layout.activeTabId)
        ? layout.activeTabId
        : keys.firstOrNull;
    return copyWith(paneLayout: layout, tabKeys: keys, activeKey: active);
  }

  ExperimentalWorkspacePanel applyMainLayout(WorkbenchLayout layout) {
    final keys = experimentalLayoutKeys(layout);
    final primary = keys.length == 1 ? tabId(keys.single) : null;
    return copyWith(mainLayout: layout, primaryTabId: primary);
  }

  ExperimentalWorkspacePanel reconcile(
    List<WorkspaceTabRecord> tabs, {
    String? preferredPrimaryId,
    String? workspaceId,
  }) {
    final candidates = tabs.where(isExperimentalPrimaryCandidate).toList();
    final preferred =
        candidates.where((tab) => tab.id == primaryTabId).firstOrNull ??
        candidates.where((tab) => tab.id == preferredPrimaryId).firstOrNull ??
        candidates.firstOrNull;
    final validTabKeys = <String>{for (final tab in tabs) tabKey(tab.id)};
    var main = ensuredMainLayout(workspaceId ?? mainLayout?.workspaceId);
    var mainKeySet = experimentalLayoutKeys(main)
        .where(
          (key) =>
              ExperimentalWorkspaceTool.forKey(key) != null ||
              validTabKeys.contains(key),
        )
        .toSet();
    main = main.sanitizeIds(mainKeySet, orphanGroupId: main.activeGroupId);
    mainKeySet = experimentalLayoutKeys(main).toSet();
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
            (ExperimentalWorkspaceTool.forKey(key) != null ||
                availableRight.contains(key)))
          key,
      ...availableRight,
    };
    final currentRight = ensuredLayout(workspaceId ?? paneLayout?.workspaceId);
    final right = currentRight.sanitizeIds(
      rightKeys,
      orphanGroupId: currentRight.activeGroupId,
    );
    final rightList = experimentalLayoutKeys(right);
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

  ExperimentalPanelTree? treeForKey(String key) {
    if (ensuredMainLayout().groupIdForTab(key) != null) {
      return ExperimentalPanelTree.main;
    }
    if (ensuredLayout().groupIdForTab(key) != null) {
      return ExperimentalPanelTree.right;
    }
    return null;
  }

  ExperimentalPanelTree? treeForGroup(String groupId) {
    if (ensuredMainLayout().groups.containsKey(groupId)) {
      return ExperimentalPanelTree.main;
    }
    if (ensuredLayout().groups.containsKey(groupId)) {
      return ExperimentalPanelTree.right;
    }
    return null;
  }

  ExperimentalWorkspacePanel select(String key, {String? groupId}) {
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

  ExperimentalWorkspacePanel closeTool(ExperimentalWorkspaceTool tool) {
    return closeKey(tool.key);
  }

  ExperimentalWorkspacePanel closeKey(String key) {
    final main = mainLayout ?? ensuredMainLayout();
    if (main.groupIdForTab(key) != null) {
      final next = applyMainLayout(main.removeTab(key));
      return next.copyWith(
        focusedKey: focusedKey == key
            ? (next.mainKeys.firstOrNull ?? next.activeKey)
            : focusedKey,
      );
    }
    final layout = paneLayout ?? ensuredLayout();
    if (layout.groupIdForTab(key) == null && !tabKeys.contains(key)) {
      return this;
    }
    final next = applyPaneLayout(layout.removeTab(key));
    final active = next.activeKey;
    return next.copyWith(
      focusedKey: focusedKey == key
          ? active ?? (primaryTabId == null ? null : tabKey(primaryTabId!))
          : focusedKey,
    );
  }

  ExperimentalWorkspacePanel moveKey({
    required String key,
    required ExperimentalPanelTree target,
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
    final dest = target == ExperimentalPanelTree.main
        ? sourceMain
        : sourceRight;
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
    final next = target == ExperimentalPanelTree.main
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
