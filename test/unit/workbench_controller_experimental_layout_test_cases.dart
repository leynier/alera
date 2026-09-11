part of 'workbench_controller_test.dart';

void _registerExperimentalLayoutTests() {
  test(
    'Experimental closing its final tool returns keyboard focus to the primary',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      _controller.selectExperimentalPanelKey(
        workspace.id,
        ExperimentalWorkspacePanel.tabKey(primary.id),
      );
      final handle = _harness.terminalRuntime.peekSession(
        primary.id,
      ) as _FakeTerminalSessionHandle;
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      final before = handle.requestFocusCalls;
      _controller.closeExperimentalTool(
        workspace.id,
        ExperimentalWorkspaceTool.search,
      );
      expect(handle.requestFocusCalls, greaterThan(before));
      expect(_controller.state.activeWorkspaceTab?.id, primary.id);
    },
  );

  test(
    'Experimental focus and tools preserve Classic splits and terminal handles',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      final secondary = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: _controller.state.activeLayout!.activeGroupId,
        zone: WorkbenchDropZone.right,
      );
      final classic = _controller.state.activeLayout!;
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      expect(
        _controller.state.experimentalPanelFor(workspace.id).primaryTabId,
        secondary.id,
      );
      _controller.selectExperimentalPanelKey(
        workspace.id,
        ExperimentalWorkspacePanel.tabKey(primary.id),
      );
      expect(_controller.state.activeWorkspaceTab?.id, primary.id);
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      expect(
        _controller.state
            .experimentalPanelFor(workspace.id)
            .tabKeys
            .where((key) => key == 'tool:search'),
        hasLength(1),
      );
      expect(_controller.state.activeWorkspaceTab, isNull);
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: workspace,
      );
      expect(_controller.state.activeWorkspaceTab?.id, secondary.id);
      expect(
        _controller.state.experimentalPanelFor(workspace.id).activeKey,
        'tool:search',
      );
      _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.classic);
      expect(_controller.state.activeLayout, classic);
      expect(_harness.terminalRuntime.closedTabIds, isEmpty);
      expect(_harness.terminalRuntime.releasedTabIds, isEmpty);
    },
  );

  test(
    'Experimental routes new terminals and file previews to the right',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
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
      final panel = _controller.state.experimentalPanelFor(workspace.id);
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
        _controller.state.experimentalPanelFor(workspace.id).tabKeys,
        panel.tabKeys,
      );
      expect(
        _controller.state.experimentalPanelFor(workspace.id).activeKey,
        panel.activeKey,
      );
      expect(_controller.state.activeWorkspaceTab?.id, primary.id);
      expect(_harness.terminalRuntime.closedTabIds, isEmpty);
      _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.classic);
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      expect(
        _controller.state.experimentalPanelFor(workspace.id).tabKeys,
        panel.tabKeys,
      );
      expect(
        _controller.state.experimentalPanelFor(workspace.id).activeKey,
        panel.activeKey,
      );
    },
  );

  test(
    'Experimental split creates a terminal pane without rewriting Classic',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      _controller.selectExperimentalPanelKey(
        workspace.id,
        ExperimentalWorkspaceTool.search.key,
      );
      final classic = _controller.state.layoutFor(workspace.id)!;
      final groupId = _controller.state
          .experimentalPanelFor(workspace.id)
          .ensuredLayout(workspace.id)
          .activeGroupId;
      final tab = await _controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: groupId,
        zone: WorkbenchDropZone.down,
      );
      final panel = _controller.state.experimentalPanelFor(workspace.id);
      expect(panel.paneLayout!.groups.length, 2);
      expect(panel.tabKeys, contains('tab:${tab.id}'));
      expect(panel.tabKeys, contains('tool:search'));
      expect(_controller.state.layoutFor(workspace.id)!.root.isLeaf, isTrue);
      expect(
        _controller.state.layoutFor(workspace.id)!.groups.length,
        classic.groups.length,
      );
    },
  );

  test('Experimental new terminal from a pane lands in that pane', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.experimental);
    _controller.selectExperimentalPanelKey(
      workspace.id,
      ExperimentalWorkspaceTool.search.key,
    );
    final firstGroupId = _controller.state
        .experimentalPanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .activeGroupId;
    await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: WorkbenchDropZone.down,
    );
    final secondGroupId = _controller.state
        .experimentalPanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .activeGroupId;
    expect(secondGroupId, isNot(firstGroupId));
    final tab = await _controller.createTerminalTab(
      workspace,
      targetGroupId: firstGroupId,
    );
    final layout = _controller.state
        .experimentalPanelFor(workspace.id)
        .ensuredLayout(workspace.id);
    expect(layout.groups[firstGroupId]!.tabIds, contains('tab:${tab.id}'));
    expect(
      layout.groups[secondGroupId]!.tabIds,
      isNot(contains('tab:${tab.id}')),
    );
  });

  test('Experimental keepPreviewTab makes a file preview permanent', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.experimental);
    final preview = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'one.dart',
      preview: true,
    );
    expect(preview.isPreview, isTrue);
    final kept = await _controller.keepPreviewTab(preview.id);
    expect(kept.id, preview.id);
    expect(kept.isPreview, isFalse);
    expect(
      _controller.state
          .tabsFor(workspace.id)
          .singleWhere((tab) => tab.id == preview.id)
          .isPreview,
      isFalse,
    );
  });

  test(
    'Experimental restores a primary after closing it with a file still open',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      final file = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'keep.dart',
      );
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: primary.id,
      );
      await _flushUntil(
        () =>
            _controller.state.experimentalPanelFor(workspace.id).primaryTabId !=
            null,
      );
      final panel = _controller.state.experimentalPanelFor(workspace.id);
      expect(panel.primaryTabId, isNot(primary.id));
      expect(panel.tabKeys, contains('tab:${file.id}'));
      expect(_harness.terminalRuntime.closedTabIds, [primary.id]);
    },
  );

  test(
    'Experimental concurrent workspace selections create exactly one primary',
    () async {
      await _controller.bootstrap();
      await _flushUntil(
        () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
      );
      final workspace = _controller.state
          .workspacesFor(_harness.project.id)
          .single;
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      await Future.wait([
        _controller.selectWorkspace(
          project: _harness.project,
          workspace: workspace,
        ),
        _controller.selectWorkspace(
          project: _harness.project,
          workspace: workspace,
        ),
      ]);
      await _flush();
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isExperimentalPrimaryCandidate),
        hasLength(1),
      );
      expect(
        _controller.state.experimentalPanelFor(workspace.id).tabKeys,
        isEmpty,
      );
    },
  );

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

  test('Experimental panels stay independent across workspace switches and controller restart', () async {
    await _controller.bootstrap();
    final first = await _selectMainWorkspace(_controller, _harness);
    _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.experimental);
    _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
    final secondary = await _controller.createTerminalTab(first);
    _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
    final firstPanel = _controller.state.experimentalPanelFor(first.id);
    final second = (await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'simple-second',
    )).workspace;
    expect(_controller.state.experimentalPanelFor(second.id).tabKeys, isEmpty);
    _controller.setContextPanelTab(WorkbenchContextPanelTab.gitDiff);
    final secondPanel = _controller.state.experimentalPanelFor(second.id);
    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: first,
    );
    expect(
      _controller.state.experimentalPanelFor(first.id).tabKeys,
      firstPanel.tabKeys,
    );
    expect(
      _controller.state.experimentalPanelFor(first.id).activeKey,
      'tool:search',
    );
    expect(_controller.state.experimentalPanelFor(second.id), secondPanel);
    await _flush();
    final persisted = WorkbenchViewPrefs.fromJson(
      _harness.viewPrefsRepository.prefs.toMap(),
    );
    expect(persisted.desktopLayout, DesktopWorkspaceLayout.experimental);
    expect(
      persisted.experimentalPanels[first.id]!.tabKeys,
      contains('tab:${secondary.id}'),
    );
    final restarted = ProviderContainer(
      parent: _harness.container,
      overrides: [
        workbenchControllerProvider.overrideWith(WorkbenchController.new),
      ],
    );
    addTearDown(restarted.dispose);
    final restored = restarted.read(workbenchControllerProvider.notifier);
    await restored.bootstrap();
    await restored.selectWorkspace(project: _harness.project, workspace: first);
    expect(restored.state.isExperimentalLayout, isTrue);
    expect(
      restored.state.experimentalPanelFor(first.id).tabKeys,
      firstPanel.tabKeys,
    );
    expect(
      restored.state.experimentalPanelFor(first.id).activeKey,
      firstPanel.activeKey,
    );
    expect(
      restored.state.experimentalPanelFor(second.id).tabKeys,
      secondPanel.tabKeys,
    );
    expect(_harness.terminalRuntime.closedTabIds, isEmpty);
  });

  test('Experimental includes externally created tabs without replacing its primary', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final primary = _controller.state.activeWorkspaceTab!;
    _controller.setDesktopWorkspaceLayout(DesktopWorkspaceLayout.experimental);
    final external = primary.copyWith(
      id: 'external-tab',
      payload: {'terminalSessionId': 'external-session'},
    );
    await _harness.workbenchRepository.upsertWorkspaceTab(external);
    await _flush();
    final panel = _controller.state.experimentalPanelFor(workspace.id);
    expect(panel.primaryTabId, primary.id);
    expect(panel.tabKeys, contains('tab:external-tab'));
    await _controller.selectWorkspaceTab(
      workspaceId: workspace.id,
      tabId: external.id,
    );
    expect(_controller.state.activeWorkspaceTab?.id, external.id);
    expect(_controller.state.viewPrefs.rightSidebarVisible, isTrue);
  });

  test(
    'Experimental closing all terminals does not recreate a slept workspace',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.setDesktopWorkspaceLayout(
        DesktopWorkspaceLayout.experimental,
      );
      await _controller.createTerminalTab(workspace);
      await _controller.sleepWorkspace(workspace);
      await _flush();
      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.activeWorkspaceId, isNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
    },
  );
}
