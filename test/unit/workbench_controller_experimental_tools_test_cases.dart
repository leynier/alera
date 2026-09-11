part of 'workbench_controller_test.dart';

void _registerExperimentalNewWorkspaceToolsTests() {
  test('Experimental new workspace opens configured tools in order and leaves others empty', () async {
    await _controller.bootstrap();
    await _selectMainWorkspace(_controller, _harness);
    _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.experimental);
    _controller.setExperimentalNewWorkspaceTools([
      ExperimentalWorkspaceTool.sourceControl,
      ExperimentalWorkspaceTool.pullRequest,
      ExperimentalWorkspaceTool.sourceControl,
    ]);
    final first = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'tools-first',
    )).workspace;
    expect(_controller.state.experimentalPanelFor(first.id).tabKeys, [
      'tool:sourceControl',
      'tool:pullRequest',
    ]);
    expect(
      _controller.state.experimentalPanelFor(first.id).activeKey,
      'tool:sourceControl',
    );
    _controller.setExperimentalNewWorkspaceTools(
      const <ExperimentalWorkspaceTool>[],
    );
    final second = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'tools-second',
    )).workspace;
    expect(_controller.state.experimentalPanelFor(second.id).tabKeys, isEmpty);
    expect(_controller.state.experimentalPanelFor(first.id).tabKeys, [
      'tool:sourceControl',
      'tool:pullRequest',
    ]);
  });

  test(
    'Experimental new workspace keeps configured tools ahead of deferred Setup',
    () async {
      await _harness.dispose();
      _harness = _WorkbenchHarness(
        const _ManagedWorkspaceRuntimeWithDeferredSetup(_setupCommand),
      );
      _controller = _harness._controller;
      await _controller.bootstrap();
      await _flushUntil(
        () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
      );
      await _selectMainWorkspace(_controller, _harness);
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      _controller.setExperimentalNewWorkspaceTools([
        ExperimentalWorkspaceTool.sourceControl,
        ExperimentalWorkspaceTool.pullRequest,
      ]);
      final workspace = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'tools-deferred-setup',
      )).workspace;
      final tabs = _controller.state.tabsFor(workspace.id);
      final setup = tabs.where((tab) => tab.title == 'Setup').single;
      final panel = _controller.state.experimentalPanelFor(workspace.id);
      expect(panel.tabKeys, [
        'tool:sourceControl',
        'tool:pullRequest',
        ExperimentalWorkspacePanel.tabKey(setup.id),
      ]);
      expect(panel.activeKey, ExperimentalWorkspacePanel.tabKey(setup.id));
    },
  );

  test('Experimental from-prompt creation seeds tools before Setup and keeps agent focus', () async {
    await _harness.dispose();
    _harness = _WorkbenchHarness(
      const _ManagedWorkspaceRuntimeWithDeferredSetup(_setupCommand),
    );
    _controller = _harness._controller;
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );
    await _selectMainWorkspace(_controller, _harness);
    _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.experimental);
    _controller.setExperimentalNewWorkspaceTools([
      ExperimentalWorkspaceTool.sourceControl,
      ExperimentalWorkspaceTool.pullRequest,
    ]);
    final result = await _controller.createWorkspaceForPrompt(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'tools-prompt-setup',
      name: 'Tools Prompt Setup',
    );
    expect(
      _controller.state.viewPrefs.experimentalPanels[result.workspace.id],
      isNull,
    );
    final now = DateTime.utc(2026, 5, 22, 4);
    await _harness.workbenchRepository.upsertWorkspaceTab(
      WorkspaceTabRecord(
        id: 'agent-tab',
        workspaceId: result.workspace.id,
        title: 'Codex',
        createdAt: now,
        updatedAt: now,
        payload: const <String, Object?>{
          workspaceTabTerminalSessionIdPayloadKey: 'agent-tab',
        },
      ),
    );
    await _controller.completePromptWorkspaceCreation(
      creation: result,
      agentTabId: 'agent-tab',
    );
    final setup = _controller.state
        .tabsFor(result.workspace.id)
        .where((tab) => tab.title == 'Setup')
        .single;
    final panel = _controller.state.experimentalPanelFor(result.workspace.id);
    expect(panel.tabKeys, [
      'tool:sourceControl',
      'tool:pullRequest',
      ExperimentalWorkspacePanel.tabKey(setup.id),
    ]);
    expect(panel.activeKey, ExperimentalWorkspacePanel.tabKey(setup.id));
    expect(_controller.state.activeWorkspaceTab?.id, 'agent-tab');
  });
}
