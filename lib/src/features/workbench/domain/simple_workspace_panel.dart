import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'simple_workspace_panel.mapper.dart';

@MappableEnum()
enum DesktopWorkspaceLayout { classic, simple }

/// Tool keys belong to desktop preferences, never to runtime tab records.
@MappableEnum()
enum SimpleWorkspaceTool {
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

  static SimpleWorkspaceTool? forKey(String? key) =>
      values.where((tool) => tool.key == key).firstOrNull;
}

bool isSimplePrimaryCandidate(WorkspaceTabRecord tab) =>
    tab.kind == WorkspaceTabKind.terminal &&
    !tab.autoCloseOnSuccess &&
    !tab.initialCommandOnce &&
    tab.title != 'Setup';

@MappableClass()
class const SimpleWorkspacePanel({
  this.primaryTabId,
  this.tabKeys = const <String>[],
  this.activeKey,
  this.focusedKey,
}) with SimpleWorkspacePanelMappable {
  final String? primaryTabId;
  final List<String> tabKeys;
  final String? activeKey;
  final String? focusedKey;

  static String tabKey(String tabId) => 'tab:$tabId';
  static String? tabId(String? key) =>
      key != null && key.startsWith('tab:') ? key.substring(4) : null;

  SimpleWorkspacePanel reconcile(
    List<WorkspaceTabRecord> tabs, {
    String? preferredPrimaryId,
  }) {
    final candidates = tabs.where(isSimplePrimaryCandidate).toList();
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
        if (SimpleWorkspaceTool.forKey(key) != null || available.contains(key))
          key,
      ...available,
    }.toList();
    final active = keys.contains(activeKey) ? activeKey : keys.firstOrNull;
    final primaryKey = primary == null ? null : tabKey(primary.id);
    final focus = focusedKey == primaryKey || keys.contains(focusedKey)
        ? focusedKey
        : primaryKey ?? active;
    return SimpleWorkspacePanel(
      primaryTabId: primary?.id,
      tabKeys: keys,
      activeKey: active,
      focusedKey: focus,
    );
  }

  SimpleWorkspacePanel select(String key) {
    if (key == tabKey(primaryTabId ?? '')) {
      return copyWith(focusedKey: key);
    }
    return copyWith(
      tabKeys: <String>[...tabKeys, if (!tabKeys.contains(key)) key],
      activeKey: key,
      focusedKey: key,
    );
  }

  SimpleWorkspacePanel closeTool(SimpleWorkspaceTool tool) {
    final keys = tabKeys.where((key) => key != tool.key).toList();
    final active = activeKey == tool.key ? keys.firstOrNull : activeKey;
    return copyWith(
      tabKeys: keys,
      activeKey: active,
      focusedKey: focusedKey == tool.key
          ? active ?? (primaryTabId == null ? null : tabKey(primaryTabId!))
          : focusedKey,
    );
  }
}
