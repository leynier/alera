part of 'workbench_controller_test.dart';

void _registerExperimentalMainPanelTests() {
  test('Experimental dropping a right tab onto main shows chrome and keeps it unique', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final primary = _controller.state.activeWorkspaceTab!;
    _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.experimental);
    _controller.selectExperimentalPanelKey(
      workspace.id,
      ExperimentalWorkspaceTool.search.key,
    );
    final mainGroup = _controller.state
        .experimentalPanelFor(workspace.id)
        .ensuredMainLayout(workspace.id)
        .activeGroupId;
    await _controller.moveExperimentalPaneTab(
      workspaceId: workspace.id,
      tabId: ExperimentalWorkspaceTool.search.key,
      targetGroupId: mainGroup,
      zone: WorkbenchDropZone.center,
      source: ExperimentalPanelTree.right,
      target: ExperimentalPanelTree.main,
    );
    final panel = _controller.state.experimentalPanelFor(workspace.id);
    expect(panel.showsMainChrome, isTrue);
    expect(panel.primaryTabId, isNull);
    expect(
      panel.mainKeys,
      containsAll([
        ExperimentalWorkspacePanel.tabKey(primary.id),
        'tool:search',
      ]),
    );
    expect(panel.tabKeys, isNot(contains('tool:search')));
    expect(panel.mainKeys.where((key) => key == 'tool:search'), hasLength(1));
    _controller.selectExperimentalPanelKey(workspace.id, 'tool:search');
    expect(
      _controller.state.experimentalPanelFor(workspace.id).focusedKey,
      'tool:search',
    );
    _controller.selectExperimentalPanelKey(
      workspace.id,
      ExperimentalWorkspacePanel.tabKey(primary.id),
    );
    expect(_controller.state.activeWorkspaceTab?.id, primary.id);
  });

  test(
    'Experimental new terminal in the main group stays off the right',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      final extra = await _controller.createTerminalTab(
        workspace,
        targetGroupId: _controller.state
            .experimentalPanelFor(workspace.id)
            .ensuredMainLayout(workspace.id)
            .activeGroupId,
      );
      final panel = _controller.state.experimentalPanelFor(workspace.id);
      expect(panel.showsMainChrome, isTrue);
      expect(
        panel.mainKeys,
        containsAll([
          ExperimentalWorkspacePanel.tabKey(primary.id),
          ExperimentalWorkspacePanel.tabKey(extra.id),
        ]),
      );
      expect(
        panel.tabKeys,
        isNot(contains(ExperimentalWorkspacePanel.tabKey(extra.id))),
      );
      expect(_controller.state.layoutFor(workspace.id)!.root.isLeaf, isTrue);
      _controller.selectExperimentalPanelKey(
        workspace.id,
        ExperimentalWorkspacePanel.tabKey(extra.id),
      );
      expect(_controller.state.activeWorkspaceTab?.id, extra.id);
    },
  );

  test(
    'Experimental split of the main group does not rewrite Classic',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      final classic = _controller.state.layoutFor(workspace.id)!;
      final tab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: _controller.state
            .experimentalPanelFor(workspace.id)
            .ensuredMainLayout(workspace.id)
            .activeGroupId,
        zone: WorkbenchDropZone.right,
      );
      final panel = _controller.state.experimentalPanelFor(workspace.id);
      expect(panel.ensuredMainLayout(workspace.id).groups.length, 2);
      expect(panel.mainKeys, contains('tab:${tab.id}'));
      expect(panel.tabKeys, isNot(contains('tab:${tab.id}')));
      expect(_controller.state.layoutFor(workspace.id)!.root.isLeaf, isTrue);
      expect(
        _controller.state.layoutFor(workspace.id)!.groups.length,
        classic.groups.length,
      );
    },
  );
}
