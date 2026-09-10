import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/domain/experimental_panel_width.dart';
import 'package:alera/src/features/workbench/domain/experimental_workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
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
  test('tool labels and tab key helpers cover every branch', () {
    expect(ExperimentalWorkspaceTool.explorer.label, 'Explorer');
    expect(ExperimentalWorkspaceTool.search.label, 'Search');
    expect(ExperimentalWorkspaceTool.sourceControl.label, 'Source Control');
    expect(ExperimentalWorkspaceTool.pullRequest.label, 'Pull Request');
    expect(ExperimentalWorkspaceTool.forKey(null), isNull);
    expect(ExperimentalWorkspaceTool.forKey('tool:missing'), isNull);
    expect(ExperimentalWorkspacePanel.tabId(null), isNull);
    expect(ExperimentalWorkspacePanel.tabId('tool:search'), isNull);
    expect(ExperimentalWorkspacePanel.tabId('tab:aux'), 'aux');
  });

  test('old preferences keep Classic and no Experimental tools', () {
    final json = WorkbenchViewPrefs.defaults.toMap()
      ..remove('desktopLayout')
      ..remove('experimentalPanels')
      ..remove('experimentalRightSidebarWidth');
    final prefs = WorkbenchViewPrefs.fromJson(json);
    expect(prefs.desktopLayout, DesktopWorkspaceLayout.classic);
    expect(prefs.experimentalPanels, isEmpty);
  });

  test('adopts active normal terminal once and retains every auxiliary', () {
    final tabs = <WorkspaceTabRecord>[
      terminal('setup', title: 'Setup'),
      terminal('first'),
      terminal('active'),
      terminal('once', payload: {'initialCommandOnce': true}),
      terminal('auto', payload: {'autoCloseOnSuccess': true}),
    ];
    final panel = const ExperimentalWorkspacePanel().reconcile(
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
      const ExperimentalWorkspacePanel()
          .reconcile(tabs, preferredPrimaryId: 'setup')
          .primaryTabId,
      'first',
    );
  });

  test(
    'stale primary promotes a normal terminal and removes stale references',
    () {
      final panel = const ExperimentalWorkspacePanel(
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
      final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
          .select(ExperimentalWorkspaceTool.search.key)
          .select(ExperimentalWorkspaceTool.search.key);
      expect(panel.tabKeys, ['tool:search']);
      expect(panel.activeKey, 'tool:search');
      final closed = panel.closeTool(ExperimentalWorkspaceTool.search);
      expect(closed.tabKeys, isEmpty);
      expect(closed.activeKey, isNull);
      expect(closed.focusedKey, 'tab:primary');
    },
  );

  test('closing a background tool preserves focus and active selection', () {
    final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .select('tool:search')
        .select('tool:explorer');
    final closed = panel.closeTool(ExperimentalWorkspaceTool.search);
    expect(closed.tabKeys, ['tool:explorer']);
    expect(closed.activeKey, 'tool:explorer');
    expect(closed.focusedKey, 'tool:explorer');
    final empty = const ExperimentalWorkspacePanel()
        .select('tool:search')
        .closeTool(ExperimentalWorkspaceTool.search);
    expect(empty.focusedKey, isNull);
    expect(empty.activeKey, isNull);
  });

  test(
    'workspace panels round trip independently with order and selection',
    () {
      final first = const ExperimentalWorkspacePanel(primaryTabId: 'first')
          .select('tool:search')
          .select('tool:explorer');
      final second = const ExperimentalWorkspacePanel(primaryTabId: 'second')
          .select('tool:pullRequest');
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        desktopLayout: DesktopWorkspaceLayout.experimental,
        experimentalPanels: {'one': first, 'two': second},
      );
      final restored = WorkbenchViewPrefs.fromJson(prefs.toMap());
      expect(restored.experimentalPanels['one'], first);
      expect(restored.experimentalPanels['two'], second);
      expect(
        restored
            .copyWith(desktopLayout: DesktopWorkspaceLayout.classic)
            .experimentalPanels,
        prefs.experimentalPanels,
      );
      expect(first.select('tab:first').activeKey, first.activeKey);
    },
  );

  test(
    'width expands beyond Classic cap and clamps without changing request',
    () {
      final maximum = experimentalPanelMaximumWidth(1600);
      expect(
        maximum,
        1600 - AleraTokens.workbenchPrimaryMinWidth - AleraTokens.space6,
      );
      expect(
        experimentalPanelMaximumWidth(740),
        greaterThan(AleraTokens.sidebarMinWidth),
      );
      expect(experimentalPanelWidth(1000, maximum), 1000);
      expect(experimentalPanelWidth(1000, 250), 250);
      expect(experimentalPanelWidth(1000, 0), 0);
      expect(
        experimentalPanelWidth(double.nan, maximum),
        AleraTokens.sidebarDefaultWidth,
      );
      expect(experimentalPanelMaximumWidth(100), 0);
      expect(experimentalPanelWidth(-1, maximum), AleraTokens.sidebarMinWidth);
    },
  );

  test('flat tabKeys migrate into a single pane group', () {
    final panel = const ExperimentalWorkspacePanel(
      tabKeys: ['tool:search', 'tab:aux'],
      activeKey: 'tool:search',
    );
    final layout = panel.ensuredLayout('workspace');
    expect(layout.groups.length, 1);
    expect(layout.activeTabId, 'tool:search');
    expect(layout.groups.values.single.tabIds, ['tool:search', 'tab:aux']);
  });

  test('splitting a tool pane keeps the tool unique', () {
    final selected = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .select('tool:search');
    final layout = selected.ensuredLayout('workspace');
    final split = selected.applyPaneLayout(
      layout.splitWithGroup(
        targetGroupId: layout.activeGroupId,
        zone: WorkbenchDropZone.down,
        newGroup: WorkbenchPaneGroup(
          id: 'pane-b',
          tabIds: const <String>['tab:term'],
          activeTabId: 'tab:term',
        ),
      ),
    );
    expect(split.tabKeys, ['tool:search', 'tab:term']);
    expect(split.paneLayout!.groups.length, 2);
    expect(
      split.paneLayout!.groups.values
          .expand((group) => group.tabIds)
          .where((key) => key == 'tool:search'),
      hasLength(1),
    );
  });

  test('moving a tool between panes does not clone it', () {
    final selected = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .select('tool:search');
    final layout = selected.ensuredLayout('workspace');
    final split = selected.applyPaneLayout(
      layout.splitWithGroup(
        targetGroupId: layout.activeGroupId,
        zone: WorkbenchDropZone.right,
        newGroup: WorkbenchPaneGroup(
          id: 'pane-b',
          tabIds: const <String>['tab:term'],
          activeTabId: 'tab:term',
        ),
      ),
    );
    final moved = split.applyPaneLayout(
      split
          .ensuredLayout('workspace')
          .moveTab(
            tabId: 'tool:search',
            targetGroupId: 'pane-b',
            zone: WorkbenchDropZone.center,
            newGroupId: 'unused',
          ),
    );
    expect(
      moved.paneLayout!.groups.values
          .expand((group) => group.tabIds)
          .where((key) => key == 'tool:search'),
      hasLength(1),
    );
    expect(moved.paneLayout!.groupIdForTab('tool:search'), 'pane-b');
  });

  test('reordering tabs inside a pane keeps them in that pane', () {
    final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .select('tool:search')
        .select('tool:explorer');
    final groupId = panel.ensuredLayout().activeGroupId;
    final reordered = panel.applyPaneLayout(
      panel.ensuredLayout().moveTab(
        tabId: 'tool:explorer',
        targetGroupId: groupId,
        zone: WorkbenchDropZone.center,
        newGroupId: 'unused',
        index: 0,
      ),
    );
    expect(reordered.ensuredLayout().groups[groupId]!.tabIds, [
      'tool:explorer',
      'tool:search',
    ]);
  });

  test('selecting a new tool can target a specific pane', () {
    final selected = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .select('tool:search');
    final layout = selected.ensuredLayout('workspace');
    final split = selected.applyPaneLayout(
      layout.splitWithGroup(
        targetGroupId: layout.activeGroupId,
        zone: WorkbenchDropZone.down,
        newGroup: WorkbenchPaneGroup(
          id: 'pane-b',
          tabIds: const <String>['tab:term'],
          activeTabId: 'tab:term',
        ),
      ),
    );
    final added = split.select('tool:explorer', groupId: 'pane-b');
    expect(added.ensuredLayout().groupIdForTab('tool:explorer'), 'pane-b');
    expect(
      added.ensuredLayout().groups[layout.activeGroupId]!.tabIds,
      isNot(contains('tool:explorer')),
    );
  });

  test('updating a pane split ratio keeps the same groups', () {
    final selected = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .select('tool:search');
    final layout = selected.ensuredLayout('workspace');
    final split = selected.applyPaneLayout(
      layout.splitWithGroup(
        targetGroupId: layout.activeGroupId,
        zone: WorkbenchDropZone.down,
        newGroup: WorkbenchPaneGroup(
          id: 'pane-b',
          tabIds: const <String>['tab:term'],
          activeTabId: 'tab:term',
        ),
      ),
    );
    expect(split.ensuredLayout().root.ratio, 0.5);
    final resized = split.applyPaneLayout(
      split.ensuredLayout().updateSplitRatio(const <int>[], 0.3),
    );
    expect(resized.ensuredLayout().root.ratio, 0.3);
    expect(resized.ensuredLayout().groups.length, 2);
  });

  test('ensuredLayout rebinds paneLayout to a new workspace id', () {
    final panel = const ExperimentalWorkspacePanel(
      tabKeys: ['tool:search'],
      activeKey: 'tool:search',
    ).select('tool:search');
    final rebound = panel.ensuredLayout('workspace-b');
    expect(rebound.workspaceId, 'workspace-b');
    expect(rebound.groups.values.single.tabIds, contains('tool:search'));
  });

  test('closeKey ignores unknown keys and select rebuilds an empty layout', () {
    final empty = const ExperimentalWorkspacePanel();
    expect(identical(empty.closeKey('tool:search'), empty), isTrue);
    final created = empty.select('tool:explorer');
    expect(created.tabKeys, ['tool:explorer']);
    expect(created.activeKey, 'tool:explorer');
  });

  test('reconcile of an empty tab list keeps an empty panel', () {
    final panel = const ExperimentalWorkspacePanel().reconcile(const []);
    expect(panel.primaryTabId, isNull);
    expect(panel.tabKeys, isEmpty);
    expect(panel.activeKey, isNull);
  });

  test('reconcile drops a stale primary when only a file remains', () {
    final file = WorkspaceTabRecord(
      id: 'file',
      workspaceId: 'workspace',
      title: 'keep.dart',
      kind: WorkspaceTabKind.editor,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final next = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .reconcile([terminal('primary')])
        .reconcile([file]);
    expect(next.primaryTabId, isNull);
    expect(next.mainKeys, isEmpty);
    expect(next.tabKeys, contains('tab:file'));
  });

  test('reconcile keeps an explicit active key still present in the panel', () {
    final panel = const ExperimentalWorkspacePanel(
      primaryTabId: 'primary',
      tabKeys: ['tool:search', 'tab:aux'],
      activeKey: 'tab:aux',
    ).reconcile([terminal('primary'), terminal('aux')]);
    expect(panel.activeKey, 'tab:aux');
  });

  test('reconcile seeds mainLayout from the primary terminal', () {
    final panel = const ExperimentalWorkspacePanel().reconcile([
      terminal('active'),
      terminal('aux'),
    ], preferredPrimaryId: 'active');
    expect(panel.primaryTabId, 'active');
    expect(panel.mainKeys, ['tab:active']);
    expect(panel.showsMainChrome, isFalse);
    expect(panel.tabKeys, contains('tab:aux'));
    expect(panel.tabKeys, isNot(contains('tab:active')));
    expect(panel.treeForKey('tab:aux'), ExperimentalPanelTree.right);
  });

  test('moving a tool from right to main keeps it unique and shows chrome', () {
    final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .reconcile([terminal('primary')])
        .select('tool:search');
    expect(panel.tabKeys, contains('tool:search'));
    final moved = panel.moveKey(
      key: 'tool:search',
      target: ExperimentalPanelTree.main,
      targetGroupId: 'missing-group',
      zone: WorkbenchDropZone.center,
      newGroupId: 'unused',
    );
    expect(moved.mainKeys, containsAll(['tab:primary', 'tool:search']));
    expect(moved.tabKeys, isNot(contains('tool:search')));
    expect(moved.showsMainChrome, isTrue);
    expect(moved.mainKeys.where((key) => key == 'tool:search'), hasLength(1));
  });

  test('edge drop onto main splits without cloning the key', () {
    final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .reconcile([terminal('primary')])
        .select('tool:explorer');
    final mainGroup = panel.ensuredMainLayout().activeGroupId;
    final split = panel.moveKey(
      key: 'tool:explorer',
      target: ExperimentalPanelTree.main,
      targetGroupId: mainGroup,
      zone: WorkbenchDropZone.right,
      newGroupId: 'main-split',
    );
    expect(split.ensuredMainLayout().groups.length, 2);
    expect(split.showsMainChrome, isTrue);
    expect(split.mainKeys.where((key) => key == 'tool:explorer'), hasLength(1));
    expect(split.tabKeys, isNot(contains('tool:explorer')));
  });

  test(
    'main and right pane groups stay distinct and accept a targeted select',
    () {
      final panel = const ExperimentalWorkspacePanel().reconcile(
        [terminal('active')],
        preferredPrimaryId: 'active',
        workspaceId: 'workspace',
      );
      final mainGroup = panel.ensuredMainLayout('workspace').activeGroupId;
      final rightGroup = panel.ensuredLayout('workspace').activeGroupId;
      expect(mainGroup, isNot(rightGroup));
      expect(panel.treeForGroup(mainGroup), ExperimentalPanelTree.main);
      expect(panel.treeForGroup(rightGroup), ExperimentalPanelTree.right);
      expect(panel.treeForGroup('missing'), isNull);
      expect(panel.treeForKey('tab:active'), ExperimentalPanelTree.main);
      final added = panel.select('tool:search', groupId: mainGroup);
      expect(added.mainKeys, contains('tool:search'));
      expect(added.tabKeys, isNot(contains('tool:search')));
      expect(added.showsMainChrome, isTrue);
      expect(added.primaryTabId, isNull);
      expect(added.select('tool:search').focusedKey, 'tool:search');
    },
  );

  test('moving a main tab back to the right hides chrome', () {
    final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .reconcile([terminal('primary')])
        .select('tool:search');
    final moved = panel.moveKey(
      key: 'tool:search',
      target: ExperimentalPanelTree.main,
      targetGroupId: panel.ensuredMainLayout().activeGroupId,
      zone: WorkbenchDropZone.center,
      newGroupId: 'unused',
    );
    expect(moved.primaryTabId, isNull);
    expect(moved.closeKey('tab:primary').focusedKey, 'tool:search');
    final restored = moved.moveKey(
      key: 'tool:search',
      target: ExperimentalPanelTree.right,
      targetGroupId: moved.ensuredLayout().activeGroupId,
      zone: WorkbenchDropZone.center,
      newGroupId: 'unused',
    );
    expect(restored.showsMainChrome, isFalse);
    expect(restored.primaryTabId, 'primary');
    expect(restored.tabKeys, contains('tool:search'));
    expect(
      restored.occupiedKeys.where((key) => key == 'tool:search'),
      hasLength(1),
    );
  });

  test(
    'closing or reconciling away an extra main tab restores the primary',
    () {
      final seeded = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
          .reconcile([terminal('primary'), terminal('aux')]);
      final panel = seeded.moveKey(
        key: 'tab:aux',
        target: ExperimentalPanelTree.main,
        targetGroupId: seeded.ensuredMainLayout().activeGroupId,
        zone: WorkbenchDropZone.center,
        newGroupId: 'unused',
      );
      expect(panel.showsMainChrome, isTrue);
      expect(panel.closeKey('tab:aux').primaryTabId, 'primary');
      expect(
        panel.reconcile([terminal('primary')]).tabKeys,
        isNot(contains('tab:aux')),
      );
    },
  );

  test('mainLayout round trips in view preferences', () {
    final panel = const ExperimentalWorkspacePanel(primaryTabId: 'primary')
        .reconcile([terminal('primary')])
        .select('tool:search');
    final moved = panel.moveKey(
      key: 'tool:search',
      target: ExperimentalPanelTree.main,
      targetGroupId: panel.ensuredMainLayout().activeGroupId,
      zone: WorkbenchDropZone.down,
      newGroupId: 'main-split',
    );
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      desktopLayout: DesktopWorkspaceLayout.experimental,
      experimentalPanels: {'one': moved},
    );
    final restored = WorkbenchViewPrefs.fromJson(prefs.toMap());
    expect(restored.experimentalPanels['one'], moved);
    expect(restored.experimentalPanels['one']!.showsMainChrome, isTrue);
    expect(
      restored.experimentalPanels['one']!.ensuredMainLayout().groups.length,
      2,
    );
  });
}
