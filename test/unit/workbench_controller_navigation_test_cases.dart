part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerNavigationTests() {
  test(
    'opening a resumed tab does not return to a workspace left during lookup',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final original = await _controller.createTerminalTab(workspace);
      final other = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/resume-background',
      )).workspace;
      final resumed = original.copyWith(id: 'resumed-tab', title: 'Resumed');
      _harness.workbenchRepository._tabsByWorkspace[workspace.id] = [
        original,
        resumed,
      ];
      final gate = Completer<void>();
      _harness.workbenchRepository.findWorkspaceTabByIdGate = gate;
      final pending = _controller.openPersistedWorkspaceTab(
        workspaceId: workspace.id,
        tabId: resumed.id,
        activateOnlyIfCurrent: true,
      );
      await _flushUntil(
        () => _harness.workbenchRepository.findWorkspaceTabByIdGate == null,
      );
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: other,
      );
      gate.complete();
      await pending;
      expect(_controller.state.activeWorkspaceId, other.id);
      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        contains(resumed.id),
      );
    },
  );

  test(
    'opening a persisted fork selects it before and after a delayed tab event',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final original = await _controller.createTerminalTab(workspace);
      await _flush();
      final fork = original.copyWith(id: 'fork-tab', title: 'Fork');
      final tabs = [
        ...await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        fork,
      ];
      _harness.workbenchRepository._tabsByWorkspace[workspace.id] = tabs;
      expect(
        _controller.state.tabsFor(workspace.id).any((tab) => tab.id == fork.id),
        isFalse,
      );
      await _controller.openPersistedWorkspaceTab(
        workspaceId: workspace.id,
        tabId: fork.id,
      );
      expect(_controller.state.activeWorkspaceTab?.id, fork.id);
      _harness.workbenchRepository._tabControllers[workspace.id]?.add(tabs);
      await _flush();
      expect(_controller.state.activeWorkspaceTab?.id, fork.id);
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where((tab) => tab.id == original.id),
        hasLength(1),
      );
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where((tab) => tab.id == fork.id),
        hasLength(1),
      );
    },
  );

  test('opening a persisted tab into a right split stays in that pane after a delayed tab event', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
    await _flush();
    final extra = await _controller.createTerminalTab(workspace);
    await _flush();
    final firstGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .activeGroupId;
    final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: .right,
    );
    await _flush();
    final splitLayout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id);
    final secondGroupId = splitLayout.groupIdForTab(
      WorkspacePanel.tabKey(splitTab.id),
    )!;
    expect(secondGroupId, isNot(firstGroupId));

    final launched = extra.copyWith(id: 'right-profile-tab', title: 'Shown');
    final tabs = [
      ...await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      launched,
    ];
    _harness.workbenchRepository._tabsByWorkspace[workspace.id] = tabs;
    _harness.workbenchRepository._tabControllers[workspace.id]?.add(tabs);
    await _flush();

    await _controller.openPersistedWorkspaceTab(
      workspaceId: workspace.id,
      tabId: launched.id,
      targetGroupId: secondGroupId,
    );
    await _flush();
    _harness.workbenchRepository._tabControllers[workspace.id]?.add(tabs);
    await _flush();

    final layout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id);
    expect(
      layout.groupIdForTab(WorkspacePanel.tabKey(launched.id)),
      secondGroupId,
    );
    expect(
      layout.groups.values.where(
        (group) => group.tabIds.contains(WorkspacePanel.tabKey(launched.id)),
      ),
      hasLength(1),
    );
  });

  test('completing a delayed pull-request open keeps a singleton destination split', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
    await _flush();
    final extra = await _controller.createTerminalTab(workspace);
    await _flush();
    final firstGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .activeGroupId;
    final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: .right,
    );
    await _flush();
    final splitGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .groupIdForTab(WorkspacePanel.tabKey(splitTab.id))!;
    final extraGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .groupIdForTab(WorkspacePanel.tabKey(extra.id))!;

    final gate = Completer<void>();
    _harness.gitBackend.persistHostedReviewRangeGate = gate;
    final delayed = _controller.openGitPullRequestDiffTab(
      workspace: workspace,
      pullRequestNumber: 12,
      commitOid: 'head-12',
      parentOid: 'base-12',
      retentionId: 'retention-split',
      targetGroupId: extraGroupId,
    );
    await _flushUntil(
      () => _harness.gitBackend.persistHostedReviewRangeGate == null,
    );
    _harness.workbenchRepository.emitTabs(workspace.id);
    await _flushUntil(
      () => _controller.state
          .tabsFor(workspace.id)
          .any((tab) => tab.kind == WorkspaceTabKind.gitDiff),
    );
    final published = _controller.state
        .tabsFor(workspace.id)
        .firstWhere((tab) => tab.kind == WorkspaceTabKind.gitDiff);
    await _controller.moveWorkspacePaneTab(
      workspaceId: workspace.id,
      tabId: extra.id,
      targetGroupId: splitGroupId,
      zone: WorkbenchDropZone.center,
      source: WorkspacePanelTree.right,
      target: WorkspacePanelTree.right,
    );
    await _flush();
    gate.complete();
    await delayed;
    await _flush();

    final layout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id);
    expect(
      layout.groupIdForTab(WorkspacePanel.tabKey(published.id)),
      extraGroupId,
    );
    expect(layout.groups.containsKey(extraGroupId), isTrue);
    expect(
      layout.groups.values.where(
        (group) => group.tabIds.contains(WorkspacePanel.tabKey(published.id)),
      ),
      hasLength(1),
    );
  });

  test('reopening a persisted tab into its current singleton split keeps that pane', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
    await _flush();
    final extra = await _controller.createTerminalTab(workspace);
    await _flush();
    final firstGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .activeGroupId;
    final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: .right,
    );
    await _flush();
    final splitGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .groupIdForTab(WorkspacePanel.tabKey(splitTab.id))!;

    await _controller.openPersistedWorkspaceTab(
      workspaceId: workspace.id,
      tabId: splitTab.id,
      targetGroupId: splitGroupId,
    );
    await _flush();

    final layout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id);
    expect(
      layout.groupIdForTab(WorkspacePanel.tabKey(splitTab.id)),
      splitGroupId,
    );
    expect(layout.groups.length, greaterThan(1));
    expect(extra.id, isNot(splitTab.id));
  });

  test('opening a persisted tab into a split pane stays in that pane after a delayed tab event', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.createTerminalTab(workspace);
    await _flush();
    final firstGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id)
        .activeGroupId;
    final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: .right,
    );
    await _flush();
    final splitLayout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id);
    final secondGroupId = splitLayout.groupIdForTab(
      WorkspacePanel.tabKey(splitTab.id),
    )!;
    expect(secondGroupId, isNot(firstGroupId));

    final launched = splitTab.copyWith(id: 'profile-tab', title: 'Shown Codex');
    final tabs = [
      ...await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      launched,
    ];
    _harness.workbenchRepository._tabsByWorkspace[workspace.id] = tabs;
    _harness.workbenchRepository._tabControllers[workspace.id]?.add(tabs);
    await _flush();
    expect(
      _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .groupIdForTab(WorkspacePanel.tabKey(launched.id)),
      isNull,
    );

    await _controller.openPersistedWorkspaceTab(
      workspaceId: workspace.id,
      tabId: launched.id,
      targetGroupId: secondGroupId,
    );
    await _flush();

    final layout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id);
    expect(
      layout.groupIdForTab(WorkspacePanel.tabKey(launched.id)),
      secondGroupId,
    );
    expect(layout.activeGroupId, secondGroupId);
    expect(layout.activeTabId, WorkspacePanel.tabKey(launched.id));
    expect(
      layout.groups.values.where(
        (group) => group.tabIds.contains(WorkspacePanel.tabKey(launched.id)),
      ),
      hasLength(1),
    );
  });

  test('opening a persisted tab into a split pane stays there after a later tab event', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.createTerminalTab(workspace);
    await _flush();
    final firstGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id)
        .activeGroupId;
    final splitTab = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: .right,
    );
    await _flush();
    final splitLayout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id);
    final secondGroupId = splitLayout.groupIdForTab(
      WorkspacePanel.tabKey(splitTab.id),
    )!;
    expect(secondGroupId, isNot(firstGroupId));

    final launched = splitTab.copyWith(
      id: 'profile-tab-later',
      title: 'Shown Codex',
    );
    final tabs = [
      ...await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      launched,
    ];
    _harness.workbenchRepository._tabsByWorkspace[workspace.id] = tabs;
    expect(
      _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .groupIdForTab(WorkspacePanel.tabKey(launched.id)),
      isNull,
    );

    await _controller.openPersistedWorkspaceTab(
      workspaceId: workspace.id,
      tabId: launched.id,
      targetGroupId: secondGroupId,
    );
    expect(
      _controller.state
          .workspacePanelFor(workspace.id)
          .ensuredMainLayout(workspace.id)
          .groupIdForTab(WorkspacePanel.tabKey(launched.id)),
      secondGroupId,
    );

    _harness.workbenchRepository._tabControllers[workspace.id]?.add(tabs);
    await _flush();

    final layout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id);
    expect(
      layout.groupIdForTab(WorkspacePanel.tabKey(launched.id)),
      secondGroupId,
    );
    expect(layout.activeGroupId, secondGroupId);
    expect(layout.activeTabId, WorkspacePanel.tabKey(launched.id));
    expect(
      layout.groups.values.where(
        (group) => group.tabIds.contains(WorkspacePanel.tabKey(launched.id)),
      ),
      hasLength(1),
    );
  });
}
