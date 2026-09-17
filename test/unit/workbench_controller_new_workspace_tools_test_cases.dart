part of 'workbench_controller_test.dart';

void _registerNewWorkspaceToolsTests() {
  test(
    'new workspace opens configured tools in order and leaves others empty',
    () async {
      await _controller.bootstrap();
      await _selectMainWorkspace(_controller, _harness);
      _controller.setNewWorkspaceTools([
        WorkspaceTool.sourceControl,
        WorkspaceTool.pullRequest,
        WorkspaceTool.sourceControl,
      ]);
      final first = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'tools-first',
      )).workspace;
      expect(_controller.state.workspacePanelFor(first.id).tabKeys, [
        'tool:sourceControl',
        'tool:pullRequest',
      ]);
      expect(
        _controller.state.workspacePanelFor(first.id).activeKey,
        'tool:sourceControl',
      );
      _controller.setNewWorkspaceTools(const <WorkspaceTool>[]);
      final second = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'tools-second',
      )).workspace;
      expect(_controller.state.workspacePanelFor(second.id).tabKeys, isEmpty);
      expect(_controller.state.workspacePanelFor(first.id).tabKeys, [
        'tool:sourceControl',
        'tool:pullRequest',
      ]);
    },
  );

  test(
    'new workspace keeps configured tools ahead of deferred Setup',
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
      _controller.setNewWorkspaceTools([
        WorkspaceTool.sourceControl,
        WorkspaceTool.pullRequest,
      ]);
      final workspace = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'tools-deferred-setup',
      )).workspace;
      final tabs = _controller.state.tabsFor(workspace.id);
      final setup = tabs.where((tab) => tab.title == 'Setup').single;
      final panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.tabKeys, [
        'tool:sourceControl',
        'tool:pullRequest',
        WorkspacePanel.tabKey(setup.id),
      ]);
      expect(panel.activeKey, WorkspacePanel.tabKey(setup.id));
    },
  );

  test(
    'from-prompt creation seeds tools before Setup and keeps agent focus',
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
      _controller.setNewWorkspaceTools([
        WorkspaceTool.sourceControl,
        WorkspaceTool.pullRequest,
      ]);
      final result = await _controller.createWorkspaceForPrompt(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'tools-prompt-setup',
        name: 'Tools Prompt Setup',
      );
      expect(
        _controller.state.viewPrefs.workspacePanels[result.workspace.id],
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
      final panel = _controller.state.workspacePanelFor(result.workspace.id);
      expect(panel.tabKeys, [
        'tool:sourceControl',
        'tool:pullRequest',
        WorkspacePanel.tabKey(setup.id),
      ]);
      expect(panel.activeKey, WorkspacePanel.tabKey(setup.id));
      expect(_controller.state.activeWorkspaceTab?.id, 'agent-tab');
    },
  );
}
