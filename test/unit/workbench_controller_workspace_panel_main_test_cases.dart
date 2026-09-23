part of 'workbench_controller_test.dart';

void _registerWorkspacePanelMainTests() {
  test('opening a file into a main group stays off the right', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.selectWorkspacePanelKey(workspace.id, WorkspaceTool.search.key);
    final mainGroup = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id)
        .activeGroupId;
    final tab = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/main.dart',
      targetGroupId: mainGroup,
    );
    await _flush();
    final panel = _controller.state.workspacePanelFor(workspace.id);
    final key = WorkspacePanel.tabKey(tab.id);
    expect(panel.mainKeys, contains(key));
    expect(panel.tabKeys, isNot(contains(key)));
  });

  test(
    'dropping a right tab onto main shows chrome and keeps it unique',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspaceTool.search.key,
      );
      final mainGroup = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .activeGroupId;
      await _controller.moveWorkspacePaneTab(
        workspaceId: workspace.id,
        tabId: WorkspaceTool.search.key,
        targetGroupId: mainGroup,
        zone: WorkbenchDropZone.center,
        source: WorkspacePanelTree.right,
        target: WorkspacePanelTree.main,
      );
      final panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.showsMainChrome, isTrue);
      expect(panel.primaryTabId, isNull);
      expect(
        panel.mainKeys,
        containsAll([WorkspacePanel.tabKey(primary.id), 'tool:search']),
      );
      expect(panel.tabKeys, isNot(contains('tool:search')));
      expect(panel.mainKeys.where((key) => key == 'tool:search'), hasLength(1));
      _controller.selectWorkspacePanelKey(workspace.id, 'tool:search');
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        'tool:search',
      );
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspacePanel.tabKey(primary.id),
      );
      expect(_controller.state.activeWorkspaceTab?.id, primary.id);
    },
  );

  test('new terminal in the main group stays off the right', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final primary = _controller.state.activeWorkspaceTab!;
    final extra = await _controller.createTerminalTab(
      workspace,
      targetGroupId: _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .activeGroupId,
    );
    final panel = _controller.state.workspacePanelFor(workspace.id);
    expect(panel.showsMainChrome, isTrue);
    expect(
      panel.mainKeys,
      containsAll([
        WorkspacePanel.tabKey(primary.id),
        WorkspacePanel.tabKey(extra.id),
      ]),
    );
    expect(panel.tabKeys, isNot(contains(WorkspacePanel.tabKey(extra.id))));
    expect(_controller.state.layoutFor(workspace.id)!.root.isLeaf, isTrue);
    _controller.selectWorkspacePanelKey(
      workspace.id,
      WorkspacePanel.tabKey(extra.id),
    );
    expect(_controller.state.activeWorkspaceTab?.id, extra.id);
  });

  test(
    'split of the main group does not rewrite the persisted tab tree',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final persisted = _controller.state.layoutFor(workspace.id)!;
      final tab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: _controller.state
            .workspacePanelFor(workspace.id)
            .ensuredMainLayout(workspace.id)
            .activeGroupId,
        zone: WorkbenchDropZone.right,
      );
      final panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.ensuredMainLayout(workspace.id).groups.length, 2);
      expect(panel.mainKeys, contains('tab:${tab.id}'));
      expect(panel.tabKeys, isNot(contains('tab:${tab.id}')));
      expect(_controller.state.layoutFor(workspace.id)!.root.isLeaf, isTrue);
      expect(
        _controller.state.layoutFor(workspace.id)!.groups.length,
        persisted.groups.length,
      );
    },
  );
}
