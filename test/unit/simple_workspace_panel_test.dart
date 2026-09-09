import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/simple_panel_width.dart';
import 'package:alera/src/features/workbench/domain/simple_workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceTabRecord terminal(
  String id, {
  Map<String, dynamic> payload = const {},
  String? title,
}) => WorkspaceTabRecord(
  id: id,
  workspaceId: 'workspace',
  title: title ?? id,
  payload: payload,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('old preferences keep Classic and no Simple tools', () {
    final json = WorkbenchViewPrefs.defaults.toMap()
      ..remove('desktopLayout')
      ..remove('simplePanels')
      ..remove('simpleRightSidebarWidth');
    final prefs = WorkbenchViewPrefs.fromJson(json);
    expect(prefs.desktopLayout, DesktopWorkspaceLayout.classic);
    expect(prefs.simplePanels, isEmpty);
  });

  test('adopts active normal terminal once and retains every auxiliary', () {
    final tabs = <WorkspaceTabRecord>[
      terminal('setup', title: 'Setup'),
      terminal('first'),
      terminal('active'),
      terminal('once', payload: {'initialCommandOnce': true}),
      terminal('auto', payload: {'autoCloseOnSuccess': true}),
    ];
    final panel = const SimpleWorkspacePanel().reconcile(
      tabs,
      preferredPrimaryId: 'active',
    );
    expect(panel.primaryTabId, 'active');
    expect(panel.tabKeys, ['tab:setup', 'tab:first', 'tab:once', 'tab:auto']);
    expect(
      panel.reconcile(tabs, preferredPrimaryId: 'first').primaryTabId,
      'active',
    );
    expect(
      const SimpleWorkspacePanel()
          .reconcile(tabs, preferredPrimaryId: 'setup')
          .primaryTabId,
      'first',
    );
  });

  test(
    'stale primary promotes a normal terminal and removes stale references',
    () {
      final panel = const SimpleWorkspacePanel(
        primaryTabId: 'deleted',
        tabKeys: ['tab:stale', 'tool:search', 'tab:next'],
        activeKey: 'tab:stale',
        focusedKey: 'tab:deleted',
      ).reconcile([terminal('setup', title: 'Setup'), terminal('next')]);
      expect(panel.primaryTabId, 'next');
      expect(panel.tabKeys, ['tool:search', 'tab:setup']);
      expect(panel.activeKey, 'tool:search');
      expect(panel.focusedKey, 'tab:next');
    },
  );

  test(
    'tools are singleton and closing the last tool restores an empty panel',
    () {
      final panel = const SimpleWorkspacePanel(primaryTabId: 'primary')
          .select(SimpleWorkspaceTool.search.key)
          .select(SimpleWorkspaceTool.search.key);
      expect(panel.tabKeys, ['tool:search']);
      expect(panel.activeKey, 'tool:search');
      final closed = panel.closeTool(SimpleWorkspaceTool.search);
      expect(closed.tabKeys, isEmpty);
      expect(closed.activeKey, isNull);
      expect(closed.focusedKey, 'tab:primary');
    },
  );

  test('closing a background tool preserves focus and active selection', () {
    final panel = const SimpleWorkspacePanel(primaryTabId: 'primary')
        .select('tool:search')
        .select('tool:explorer');
    final closed = panel.closeTool(SimpleWorkspaceTool.search);
    expect(closed.tabKeys, ['tool:explorer']);
    expect(closed.activeKey, 'tool:explorer');
    expect(closed.focusedKey, 'tool:explorer');
    final empty = const SimpleWorkspacePanel()
        .select('tool:search')
        .closeTool(SimpleWorkspaceTool.search);
    expect(empty.focusedKey, isNull);
    expect(empty.activeKey, isNull);
  });

  test(
    'workspace panels round trip independently with order and selection',
    () {
      final first = const SimpleWorkspacePanel(primaryTabId: 'first')
          .select('tool:search')
          .select('tool:explorer');
      final second = const SimpleWorkspacePanel(primaryTabId: 'second')
          .select('tool:pullRequest');
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        desktopLayout: DesktopWorkspaceLayout.simple,
        simplePanels: {'one': first, 'two': second},
      );
      final restored = WorkbenchViewPrefs.fromJson(prefs.toMap());
      expect(restored.simplePanels['one'], first);
      expect(restored.simplePanels['two'], second);
      expect(
        restored
            .copyWith(desktopLayout: DesktopWorkspaceLayout.classic)
            .simplePanels,
        prefs.simplePanels,
      );
      expect(first.select('tab:first').activeKey, first.activeKey);
    },
  );

  test(
    'width expands beyond Classic cap and clamps without changing request',
    () {
      final maximum = simplePanelMaximumWidth(1600);
      expect(
        maximum,
        1600 - AleraTokens.workbenchPrimaryMinWidth - AleraTokens.space6,
      );
      expect(
        simplePanelMaximumWidth(740),
        greaterThan(AleraTokens.sidebarMinWidth),
      );
      expect(simplePanelWidth(1000, maximum), 1000);
      expect(simplePanelWidth(1000, 250), 250);
      expect(simplePanelWidth(1000, 0), 0);
      expect(
        simplePanelWidth(double.nan, maximum),
        AleraTokens.sidebarDefaultWidth,
      );
      expect(simplePanelMaximumWidth(100), 0);
      expect(simplePanelWidth(-1, maximum), AleraTokens.sidebarMinWidth);
    },
  );
}
