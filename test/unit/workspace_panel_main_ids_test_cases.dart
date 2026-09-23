part of 'workspace_panel_test.dart';

void _registerWorkspacePanelMainIdsTests() {
  test('shared main tab ids come from the main panel, not the right pane', () {
    final panel = const WorkspacePanel()
        .reconcile([terminal('primary'), terminal('side')])
        .select('tab:side');
    expect(workspacePanelMainTabIds(panel), <String>['primary']);
    expect(panel.tabKeys, contains('tab:side'));
    expect(sharedWorkspaceMainTabIds({'ws': panel}), {
      'ws': <String>['primary'],
    });
    expect(
      workspacePanelMainTabIds(const WorkspacePanel(primaryTabId: 'seeded')),
      <String>['seeded'],
    );
    expect(
      sharedWorkspaceMainTabIds(const <String, WorkspacePanel>{}),
      isEmpty,
    );
  });

  test(
    'closing or reconciling away an extra main tab restores the primary',
    () {
      final seeded = const WorkspacePanel(primaryTabId: 'primary')
          .reconcile([terminal('primary'), terminal('aux')]);
      final panel = seeded.moveKey(
        key: 'tab:aux',
        target: WorkspacePanelTree.main,
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
    final panel = const WorkspacePanel(primaryTabId: 'primary')
        .reconcile([terminal('primary')])
        .select('tool:search');
    final moved = panel.moveKey(
      key: 'tool:search',
      target: WorkspacePanelTree.main,
      targetGroupId: panel.ensuredMainLayout().activeGroupId,
      zone: WorkbenchDropZone.down,
      newGroupId: 'main-split',
    );
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      workspacePanels: {'one': moved},
    );
    final restored = WorkbenchViewPrefs.fromJson(prefs.toMap());
    expect(restored.workspacePanels['one'], moved);
    expect(restored.workspacePanels['one']!.showsMainChrome, isTrue);
    expect(
      restored.workspacePanels['one']!.ensuredMainLayout().groups.length,
      2,
    );
  });
}
