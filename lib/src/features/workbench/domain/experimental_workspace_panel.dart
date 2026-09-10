import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'experimental_workspace_panel.mapper.dart';

@MappableEnum()
enum DesktopWorkspaceLayout { classic, experimental }

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

@MappableClass()
class const ExperimentalWorkspacePanel({
  this.primaryTabId,
  this.tabKeys = const <String>[],
  this.activeKey,
  this.focusedKey,
  this.paneLayout,
}) with ExperimentalWorkspacePanelMappable {
  final String? primaryTabId;
  final List<String> tabKeys;
  final String? activeKey;
  final String? focusedKey;
  final WorkbenchLayout? paneLayout;

  static String tabKey(String tabId) => 'tab:$tabId';
  static String? tabId(String? key) =>
      key != null && key.startsWith('tab:') ? key.substring(4) : null;

  static const String fallbackLayoutWorkspaceId = 'experimental-panel';

  WorkbenchLayout ensuredLayout([String? workspaceId]) {
    final existing = paneLayout;
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
      tabIds: tabKeys,
    );
    final active = activeKey;
    final groupId = active == null ? null : layout.groupIdForTab(active);
    if (active == null || groupId == null) {
      return layout;
    }
    return layout.setActiveTab(groupId: groupId, tabId: active);
  }

  ExperimentalWorkspacePanel applyPaneLayout(WorkbenchLayout layout) {
    final keys = <String>[
      for (final groupId in layout.paneGroupIds)
        ...layout.groups[groupId]?.tabIds ?? const <String>[],
    ];
    final active = keys.contains(layout.activeTabId)
        ? layout.activeTabId
        : keys.firstOrNull;
    return copyWith(paneLayout: layout, tabKeys: keys, activeKey: active);
  }

  ExperimentalWorkspacePanel reconcile(
    List<WorkspaceTabRecord> tabs, {
    String? preferredPrimaryId,
    String? workspaceId,
  }) {
    final candidates = tabs.where(isExperimentalPrimaryCandidate).toList();
    final primary =
        candidates.where((tab) => tab.id == primaryTabId).firstOrNull ??
        candidates.where((tab) => tab.id == preferredPrimaryId).firstOrNull ??
        candidates.firstOrNull;
    final available = <String>{
      for (final tab in tabs)
        if (tab.id != primary?.id) tabKey(tab.id),
    };
    final keys = <String>{
      for (final key in tabKeys)
        if (ExperimentalWorkspaceTool.forKey(key) != null ||
            available.contains(key))
          key,
      ...available,
    };
    final current = ensuredLayout(workspaceId ?? paneLayout?.workspaceId);
    final layout = current.sanitizeIds(
      keys,
      orphanGroupId: current.activeGroupId,
    );
    final primaryKey = primary == null ? null : tabKey(primary.id);
    final active = keys.contains(layout.activeTabId)
        ? layout.activeTabId
        : keys.firstOrNull;
    final focused = focusedKey == primaryKey || keys.contains(focusedKey)
        ? focusedKey
        : primaryKey ?? active;
    var next = applyPaneLayout(layout)
        .copyWith(primaryTabId: primary?.id, focusedKey: focused);
    if (active != null && next.paneLayout?.groupIdForTab(active) != null) {
      next = next
          .applyPaneLayout(
            next.paneLayout!.setActiveTab(
              groupId: next.paneLayout!.groupIdForTab(active)!,
              tabId: active,
            ),
          )
          .copyWith(focusedKey: focused);
    }
    return next;
  }

  ExperimentalWorkspacePanel select(String key, {String? groupId}) {
    if (key == tabKey(primaryTabId ?? '')) {
      return copyWith(focusedKey: key);
    }
    final layout = ensuredLayout();
    final existingGroupId = layout.groupIdForTab(key);
    if (existingGroupId != null) {
      return applyPaneLayout(
        layout.setActiveTab(groupId: existingGroupId, tabId: key),
      ).copyWith(focusedKey: key);
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
}
