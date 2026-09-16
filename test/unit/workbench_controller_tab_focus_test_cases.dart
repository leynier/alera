part of 'workbench_controller_test.dart';

/// Which tab takes focus once the active one is gone.
void _registerWorkbenchControllerTabFocusTests() {
  test(
    'closing the active tab refocuses the most recently focused tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      await _controller.createTerminalTab(workspace);
      final thirdTab = await _controller.createTerminalTab(workspace);
      await _flush();

      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      await _flush();
      expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);

      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: firstTab.id,
      );
      await _flush();

      expect(_controller.state.activeWorkspaceTab?.id, thirdTab.id);
    },
  );

  test('closing a background tab keeps a focused tool selected', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final primary = _controller.state.activeWorkspaceTab!;
    final extra = await _controller.createTerminalTab(workspace);
    await _flush();
    _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
    await _flush();
    expect(_controller.state.activeWorkspaceTab, isNull);

    await _controller.closeWorkspaceTab(workspace: workspace, tabId: extra.id);
    await _flush();

    expect(
      _controller.state.workspacePanelFor(workspace.id).focusedKey,
      WorkspaceTool.search.key,
    );
    expect(_controller.state.activeWorkspaceTab, isNull);
    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      contains(primary.id),
    );
  });

  test(
    'reselecting a watcher fallback tab records it as the most recent tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      final secondTab = await _controller.createTerminalTab(workspace);
      final thirdTab = await _controller.createTerminalTab(workspace);
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: thirdTab.id);
      await _flush();

      await _harness.workbenchRepository.removeWorkspaceTab(thirdTab.id);
      await _flushUntil(
        () => _controller.state
            .tabsFor(workspace.id)
            .every((tab) => tab.id != thirdTab.id),
      );
      _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
      await _flush();
      final extra = await _controller.createTerminalTab(workspace);
      await _flush();
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: extra.id,
      );
      await _flush();

      expect(_controller.state.activeWorkspaceTab?.id, secondTab.id);
    },
  );

  test(
    'closing a focused tab restores MRU even if the watcher selected a tool',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      final secondTab = await _controller.createTerminalTab(workspace);
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
      await _flush();

      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: secondTab.id,
      );
      await _flush();

      expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);
    },
  );

  test('closing a focused tab keeps a terminal opened while the close was in flight', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final firstTab = _controller.state.activeWorkspaceTab!;
    final secondTab = await _controller.createTerminalTab(workspace);
    await _flush();
    _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
    _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
    await _flush();

    final closeGate = Completer<void>();
    _harness.workbenchRepository.removeWorkspaceTabGate = closeGate;
    final closing = _controller.closeWorkspaceTab(
      workspace: workspace,
      tabId: secondTab.id,
    );
    await _flush();
    final opened = await _controller.createTerminalTab(workspace);
    await _flush();
    closeGate.complete();
    await closing;
    await _flush();

    expect(_controller.state.activeWorkspaceTab?.id, opened.id);
    expect(
      _controller.state.workspacePanelFor(workspace.id).focusedKey,
      WorkspacePanel.tabKey(opened.id),
    );
  });

  test('closing a focused tab keeps a split terminal created while the close was in flight', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final firstTab = _controller.state.activeWorkspaceTab!;
    final secondTab = await _controller.createTerminalTab(workspace);
    await _flush();
    final firstGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id)
        .activeGroupId;
    _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
    _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
    await _flush();

    final closeGate = Completer<void>();
    _harness.workbenchRepository.removeWorkspaceTabGate = closeGate;
    final closing = _controller.closeWorkspaceTab(
      workspace: workspace,
      tabId: secondTab.id,
    );
    await _flush();
    final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: .right,
    );
    await _flush();
    closeGate.complete();
    await closing;
    await _flush();

    expect(_controller.state.activeWorkspaceTab?.id, splitTab.id);
    expect(
      _controller.state.workspacePanelFor(workspace.id).focusedKey,
      WorkspacePanel.tabKey(splitTab.id),
    );
  });

  test(
    'closing a focused tab restores a live MRU if the captured target closed',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      final secondTab = await _controller.createTerminalTab(workspace);
      final thirdTab = await _controller.createTerminalTab(workspace);
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: thirdTab.id);
      await _flush();

      final closeGate = Completer<void>();
      _harness.workbenchRepository.removeWorkspaceTabGate = closeGate;
      final closingFocused = _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: thirdTab.id,
      );
      await _flush();
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: secondTab.id,
      );
      await _flush();
      closeGate.complete();
      await closingFocused;
      await _flush();

      expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspacePanel.tabKey(firstTab.id),
      );
    },
  );

  test(
    'closing a focused tab keeps a tool moved while the close was in flight',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      final secondTab = await _controller.createTerminalTab(workspace);
      await _flush();
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
      await _flush();
      final mainGroup = _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .activeGroupId;

      final closeGate = Completer<void>();
      _harness.workbenchRepository.removeWorkspaceTabGate = closeGate;
      final closing = _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: secondTab.id,
      );
      await _flush();
      await _controller.moveWorkspacePaneTab(
        workspaceId: workspace.id,
        tabId: WorkspaceTool.search.key,
        targetGroupId: mainGroup,
        zone: WorkbenchDropZone.center,
        source: WorkspacePanelTree.right,
        target: WorkspacePanelTree.main,
      );
      await _flush();
      closeGate.complete();
      await closing;
      await _flush();

      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspaceTool.search.key,
      );
      expect(_controller.state.activeWorkspaceTab, isNull);
    },
  );

  test(
    'closing a focused tab keeps the primary after the sidebar is hidden',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      final secondTab = await _controller.createTerminalTab(workspace);
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: secondTab.id);
      await _flush();

      final closeGate = Completer<void>();
      _harness.workbenchRepository.removeWorkspaceTabGate = closeGate;
      final closing = _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: secondTab.id,
      );
      await _flush();
      _controller.setRightSidebarVisible(false);
      await _flush();
      closeGate.complete();
      await closing;
      await _flush();

      expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspacePanel.tabKey(firstTab.id),
      );
    },
  );
}
