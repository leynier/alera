part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerNavigationTests() {
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

  test(
    'records worktree selection and replays back and forward safely',
    () async {
      await _controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(_controller, _harness);
      expect(_controller.canGoBack, isFalse);
      expect(_controller.canGoForward, isFalse);

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      expect(_controller.canGoBack, isFalse);

      final first = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/navigation-first',
      )).workspace;
      final second = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/navigation-second',
      )).workspace;
      expect(_controller.state.activeWorkspaceId, second.id);

      await _controller.goBack();
      expect(_controller.state.activeWorkspaceId, first.id);
      expect(_controller.canGoForward, isTrue);

      _controller.setSearchQuery('does-not-match');
      await _controller.goBack();
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);
      expect(_controller.canGoForward, isTrue);

      await _controller.goForward();
      expect(_controller.state.activeWorkspaceId, first.id);

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      expect(_controller.canGoForward, isFalse);
    },
  );

  test('skips deleted workspaces in navigation history', () async {
    await _controller.bootstrap();
    final mainWorkspace = await _selectMainWorkspace(_controller, _harness);
    final removedWorkspace = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/navigation-removed',
    )).workspace;
    final currentWorkspace = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/navigation-current',
    )).workspace;

    await _harness.workbenchRepository.removeWorkspace(removedWorkspace.id);
    await _flushUntil(
      () => !_controller.state
          .workspacesFor(_harness.project.id)
          .any((workspace) => workspace.id == removedWorkspace.id),
    );

    expect(_controller.state.activeWorkspaceId, currentWorkspace.id);
    expect(_controller.canGoBack, isTrue);
    await _controller.goBack();
    expect(_controller.state.activeWorkspaceId, mainWorkspace.id);
    expect(_controller.state.searchQuery, isEmpty);
  });

  test(
    'selectWorkspaceTab switches workspaces before focusing the tab',
    () async {
      await _controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(_controller, _harness);
      final otherWorkspace = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/codex-resume-target',
      )).workspace;
      final targetTab = _controller.state.tabsFor(otherWorkspace.id).first;

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);

      await _controller.selectWorkspaceTab(
        workspaceId: otherWorkspace.id,
        tabId: targetTab.id,
      );

      expect(_controller.state.activeWorkspaceId, otherWorkspace.id);
      expect(_controller.state.activeWorkspaceTab?.id, targetTab.id);
    },
  );

  test('prunes navigation entries when their project is removed', () async {
    await _controller.bootstrap();
    await _selectMainWorkspace(_controller, _harness);
    final secondWorkspace = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/navigation-project',
    )).workspace;
    expect(_controller.state.activeWorkspaceId, secondWorkspace.id);

    final otherProject = await _harness.addProject('project-2', 'Other');
    await _flushUntil(
      () => _controller.state.projects.any(
        (project) => project.id == otherProject.id,
      ),
    );
    await _flushUntil(
      () => _controller.state.workspacesFor(otherProject.id).isNotEmpty,
    );
    final otherWorkspace = _controller.state
        .workspacesFor(otherProject.id)
        .single;
    await _controller.selectWorkspace(
      project: otherProject,
      workspace: otherWorkspace,
    );

    await _harness.projectRepository.remove(_harness.project.id);
    await _flushUntil(
      () => !_controller.state.projects.any(
        (project) => project.id == _harness.project.id,
      ),
    );

    expect(_controller.canGoBack, isFalse);
    expect(_controller.state.activeWorkspaceId, otherWorkspace.id);
  });
}
