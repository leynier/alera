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
      expect(
        _controller.state.layoutFor(workspace.id)?.activeTabId,
        thirdTab.id,
      );
    },
  );

  test(
    'closing the active tab refocuses a tab living in another pane group',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final firstTab = _controller.state.activeWorkspaceTab!;
      final firstGroupId = _controller.state
          .layoutFor(workspace.id)!
          .activeGroupId;
      await _controller.createTerminalTab(workspace);
      final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: firstGroupId,
        zone: .right,
      );
      await _flush();

      _controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
      await _flush();
      expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);

      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: firstTab.id,
      );
      await _flush();

      final layout = _controller.state.layoutFor(workspace.id)!;
      expect(_controller.state.activeWorkspaceTab?.id, splitTab.id);
      expect(layout.activeTabId, splitTab.id);
      expect(layout.activeGroupId, layout.groupIdForTab(splitTab.id));
    },
  );
}
