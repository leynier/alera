part of 'workbench_controller_test.dart';

void _registerWorkspacePanelTests() {
  test(
    'closing its final tool returns keyboard focus to the primary',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      _harness.terminalRuntime.sessionFor(workspace: workspace, tab: primary);
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspacePanel.tabKey(primary.id),
      );
      final handle = _harness.terminalRuntime.peekSession(
        primary.id,
      ) as _FakeTerminalSessionHandle;
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      final before = handle.requestFocusCalls;
      _controller.closeWorkspaceTool(workspace.id, WorkspaceTool.search);
      expect(handle.requestFocusCalls, greaterThan(before));
      expect(_controller.state.activeWorkspaceTab?.id, primary.id);
    },
  );

  test('closing the last main tool reveals a hidden sidebar tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final terminal = _controller.state.activeWorkspaceTab!;
    final editor = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/keep.dart',
    );
    await _flush();
    _controller.setContextPanelTab(WorkbenchContextPanelTab.explorer);
    await _flush();
    final mainGroup = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id)
        .activeGroupId;
    await _controller.moveWorkspacePaneTab(
      workspaceId: workspace.id,
      tabId: WorkspaceTool.explorer.key,
      targetGroupId: mainGroup,
      zone: WorkbenchDropZone.center,
      source: WorkspacePanelTree.right,
      target: WorkspacePanelTree.main,
    );
    await _flush();
    await _controller.moveWorkspacePaneTab(
      workspaceId: workspace.id,
      tabId: terminal.id,
      targetGroupId: _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredLayout(workspace.id)
          .activeGroupId,
      zone: WorkbenchDropZone.center,
      source: WorkspacePanelTree.main,
      target: WorkspacePanelTree.right,
    );
    await _flush();
    _controller.setActiveTab(workspaceId: workspace.id, tabId: editor.id);
    await _flush();
    _controller.selectWorkspacePanelKey(
      workspace.id,
      WorkspaceTool.explorer.key,
    );
    await _flush();
    _controller.setRightSidebarVisible(false);
    await _flush();
    expect(_controller.state.viewPrefs.rightSidebarVisible, isFalse);
    expect(
      _controller.state.workspacePanelFor(workspace.id).focusedKey,
      WorkspaceTool.explorer.key,
    );

    _controller.closeWorkspaceTool(workspace.id, WorkspaceTool.explorer);
    await _flush();

    expect(_controller.state.viewPrefs.rightSidebarVisible, isTrue);
    expect(_controller.state.activeWorkspaceTab?.id, editor.id);
    expect(
      _controller.state.workspacePanelFor(workspace.id).focusedKey,
      WorkspacePanel.tabKey(editor.id),
    );
  });

  test(
    'closing a focused main tool keeps the surviving pane active tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final first = _controller.state.activeWorkspaceTab!;
      final second = await _controller.createTerminalTab(workspace);
      await _flush();
      final mainGroup = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .activeGroupId;
      await _controller.moveWorkspacePaneTab(
        workspaceId: workspace.id,
        tabId: second.id,
        targetGroupId: mainGroup,
        zone: WorkbenchDropZone.center,
        source: WorkspacePanelTree.right,
        target: WorkspacePanelTree.main,
      );
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: first.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: second.id);
      await _flush();
      _controller.setContextPanelTab(WorkbenchContextPanelTab.explorer);
      await _flush();
      await _controller.moveWorkspacePaneTab(
        workspaceId: workspace.id,
        tabId: WorkspaceTool.explorer.key,
        targetGroupId: mainGroup,
        zone: WorkbenchDropZone.right,
        source: WorkspacePanelTree.right,
        target: WorkspacePanelTree.main,
      );
      await _flush();
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspaceTool.explorer.key,
      );

      _controller.closeWorkspaceTool(workspace.id, WorkspaceTool.explorer);
      await _flush();

      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspacePanel.tabKey(second.id),
      );
      expect(_controller.state.activeWorkspaceTab?.id, second.id);
    },
  );

  test(
    'closing a non-focused split keeps the focused tab selected and displayed',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final first = _controller.state.activeWorkspaceTab!;
      final firstGroupId = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .activeGroupId;
      final second = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: firstGroupId,
        zone: WorkbenchDropZone.right,
      );
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: second.id);
      await _flush();
      expect(_controller.state.activeWorkspaceTab?.id, second.id);

      _controller.mergeWorkspacePaneIntoSibling(
        workspaceId: workspace.id,
        groupId: firstGroupId,
      );
      await _flush();

      expect(_controller.state.activeWorkspaceTab?.id, second.id);
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspacePanel.tabKey(second.id),
      );
      expect(
        _controller.state
            .workspacePanelFor(workspace.id)
            .ensuredMainLayout(workspace.id)
            .activeTabId,
        WorkspacePanel.tabKey(second.id),
      );
      expect(first.id, isNot(second.id));
    },
  );

  test(
    'focus and tools keep the persisted tab tree and terminal handles',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      final persisted = _controller.state.activeLayout!;
      final secondary = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: _controller.state
            .workspacePanelFor(workspace.id)
            .ensuredMainLayout(workspace.id)
            .activeGroupId,
        zone: WorkbenchDropZone.right,
      );
      expect(
        _controller.state.workspacePanelFor(workspace.id).showsMainChrome,
        isTrue,
      );
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspacePanel.tabKey(primary.id),
      );
      expect(_controller.state.activeWorkspaceTab?.id, primary.id);
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      expect(
        _controller.state
            .workspacePanelFor(workspace.id)
            .tabKeys
            .where((key) => key == 'tool:search'),
        hasLength(1),
      );
      expect(_controller.state.activeWorkspaceTab, isNull);
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: workspace,
      );
      expect(
        _controller.state.workspacePanelFor(workspace.id).activeKey,
        'tool:search',
      );
      expect(_controller.state.layoutFor(workspace.id)!.root.isLeaf, isTrue);
      expect(
        _controller.state.layoutFor(workspace.id)!.groups.length,
        persisted.groups.length,
      );
      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        containsAll([primary.id, secondary.id]),
      );
      expect(_harness.terminalRuntime.closedTabIds, isEmpty);
      expect(_harness.terminalRuntime.releasedTabIds, isEmpty);
    },
  );

  test('routes new terminals and file previews to the right', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final primary = _controller.state.activeWorkspaceTab!;
    final secondary = await _controller.createTerminalTab(workspace);
    expect(
      (_harness.terminalRuntime.peekSession(
        secondary.id,
      ) as _FakeTerminalSessionHandle?)?.requestFocusCalls,
      greaterThan(0),
    );
    final setup = await _controller.createTerminalTab(
      workspace,
      title: 'Setup',
      autoCloseOnSuccess: true,
    );
    final preview = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'one.dart',
      preview: true,
    );
    final replacement = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'two.dart',
      preview: true,
    );
    expect(replacement.id, preview.id);
    final panel = _controller.state.workspacePanelFor(workspace.id);
    expect(panel.primaryTabId, primary.id);
    expect(
      panel.tabKeys,
      containsAll([
        'tab:${secondary.id}',
        'tab:${setup.id}',
        'tab:${preview.id}',
      ]),
    );
    expect(panel.activeKey, 'tab:${replacement.id}');
    expect(_controller.state.activeWorkspaceTab?.id, replacement.id);
    _controller.setRightSidebarVisible(false);
    expect(
      _controller.state.workspacePanelFor(workspace.id).tabKeys,
      panel.tabKeys,
    );
    expect(
      _controller.state.workspacePanelFor(workspace.id).activeKey,
      panel.activeKey,
    );
    expect(_controller.state.activeWorkspaceTab?.id, primary.id);
    expect(_harness.terminalRuntime.closedTabIds, isEmpty);
    expect(
      _controller.state.workspacePanelFor(workspace.id).tabKeys,
      panel.tabKeys,
    );
    expect(
      _controller.state.workspacePanelFor(workspace.id).activeKey,
      panel.activeKey,
    );
  });

  test(
    'split creates a terminal pane without rewriting the persisted tab tree',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspaceTool.search.key,
      );
      final persisted = _controller.state.layoutFor(workspace.id)!;
      final groupId = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredLayout(workspace.id)
          .activeGroupId;
      final tab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: groupId,
        zone: WorkbenchDropZone.down,
      );
      final panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.paneLayout!.groups.length, 2);
      expect(panel.tabKeys, contains('tab:${tab.id}'));
      expect(panel.tabKeys, contains('tool:search'));
      expect(_controller.state.layoutFor(workspace.id)!.root.isLeaf, isTrue);
      expect(
        _controller.state.layoutFor(workspace.id)!.groups.length,
        persisted.groups.length,
      );
    },
  );

  test(
    'a delayed terminal open keeps a split created while it was in flight',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspaceTool.search.key,
      );
      final groupId = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredLayout(workspace.id)
          .activeGroupId;
      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.createTerminalTab(workspace);
      await _flush();
      final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: groupId,
        zone: WorkbenchDropZone.down,
      );
      gate.complete();
      final delayedTab = await delayed;
      await _flush();

      final tabs = _controller.state.tabsFor(workspace.id);
      expect(
        tabs.map((tab) => tab.id),
        containsAll(<String>[splitTab.id, delayedTab.id]),
      );
      expect(
        _controller.state
            .workspacePanelFor(workspace.id)
            .ensuredLayout(workspace.id)
            .groups
            .length,
        2,
      );
    },
  );

  test(
    'a delayed pull-request open keeps a split created while it was in flight',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.selectWorkspacePanelKey(
        workspace.id,
        WorkspaceTool.search.key,
      );
      final groupId = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredLayout(workspace.id)
          .activeGroupId;
      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.openGitPullRequestDiffTab(
        workspace: workspace,
        pullRequestNumber: 42,
        commitOid: 'head-42',
        parentOid: 'base-42',
        retentionId: 'retention-delayed',
      );
      await _flush();
      final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: groupId,
        zone: WorkbenchDropZone.down,
      );
      gate.complete();
      final delayedTab = await delayed;
      await _flush();

      final tabs = _controller.state.tabsFor(workspace.id);
      expect(
        tabs.map((tab) => tab.id),
        containsAll(<String>[splitTab.id, delayedTab.id]),
      );
      expect(
        _controller.state
            .workspacePanelFor(workspace.id)
            .ensuredLayout(workspace.id)
            .groups
            .length,
        2,
      );
    },
  );
}
