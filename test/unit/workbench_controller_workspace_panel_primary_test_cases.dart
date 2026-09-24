part of 'workbench_controller_test.dart';

void _registerWorkspacePanelPrimaryTests() {
  test('new terminal from a pane lands in that pane', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.selectWorkspacePanelKey(workspace.id, WorkspaceTool.search.key);
    final firstGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .activeGroupId;
    await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: firstGroupId,
      zone: WorkbenchDropZone.down,
    );
    final secondGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .activeGroupId;
    expect(secondGroupId, isNot(firstGroupId));
    final tab = await _controller.createTerminalTab(
      workspace,
      targetGroupId: firstGroupId,
    );
    final layout = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id);
    expect(layout.groups[firstGroupId]!.tabIds, contains('tab:${tab.id}'));
    expect(
      layout.groups[secondGroupId]!.tabIds,
      isNot(contains('tab:${tab.id}')),
    );
  });

  test('keepPreviewTab makes a file preview permanent', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
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

  test('restores a primary after closing it with a file still open', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final primary = _controller.state.activeWorkspaceTab!;
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
          _controller.state.workspacePanelFor(workspace.id).primaryTabId !=
          null,
    );
    final panel = _controller.state.workspacePanelFor(workspace.id);
    expect(panel.primaryTabId, isNot(primary.id));
    expect(panel.tabKeys, contains('tab:${file.id}'));
    expect(_harness.terminalRuntime.closedTabIds, [primary.id]);
  });

  test(
    'restoring a primary keeps a focused tool selected in the right pane',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      final file = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'keep.dart',
      );
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      await _flush();
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspaceTool.search.key,
      );

      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: primary.id,
      );
      await _flushUntil(
        () =>
            _controller.state.workspacePanelFor(workspace.id).primaryTabId !=
            null,
      );
      final panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.primaryTabId, isNot(primary.id));
      expect(panel.focusedKey, WorkspaceTool.search.key);
      expect(panel.tabKeys, contains('tab:${file.id}'));
      expect(panel.tabKeys, contains(WorkspaceTool.search.key));
      expect(
        panel.ensuredLayout(workspace.id).activeTabId,
        isNot('tab:${panel.primaryTabId}'),
      );
    },
  );

  test('concurrent workspace selections create exactly one primary', () async {
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );
    final workspace = _controller.state
        .workspacesFor(_harness.project.id)
        .single;
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
      _controller.state.tabsFor(workspace.id).where(isPrimaryTerminalCandidate),
      hasLength(1),
    );
    expect(_controller.state.workspacePanelFor(workspace.id).tabKeys, isEmpty);
  });

  test(
    'panels stay independent across workspace switches and controller restart',
    () async {
      await _controller.bootstrap();
      final first = await _selectMainWorkspace(_controller, _harness);
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      final secondary = await _controller.createTerminalTab(first);
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      final firstPanel = _controller.state.workspacePanelFor(first.id);
      final second = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'simple-second',
      )).workspace;
      expect(_controller.state.workspacePanelFor(second.id).tabKeys, isEmpty);
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: second,
      );
      _controller.setContextPanelTab(WorkbenchContextPanelTab.gitDiff);
      final secondPanel = _controller.state.workspacePanelFor(second.id);
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: first,
      );
      expect(
        _controller.state.workspacePanelFor(first.id).tabKeys,
        firstPanel.tabKeys,
      );
      expect(
        _controller.state.workspacePanelFor(first.id).activeKey,
        'tool:search',
      );
      expect(_controller.state.workspacePanelFor(second.id), secondPanel);
      await _flush();
      final persisted = WorkbenchViewPrefs.fromJson(
        _harness.viewPrefsRepository.prefs.toMap(),
      );
      expect(
        persisted.workspacePanels[first.id]!.tabKeys,
        contains('tab:${secondary.id}'),
      );
      final restarted = ProviderContainer(
        parent: _harness.container,
        overrides: [
          // Root provider, overridden in a child container so persisted
          // view prefs survive a controller restart.
          // ignore: riverpod_lint/scoped_providers_should_specify_dependencies
          workbenchControllerProvider.overrideWith(WorkbenchController.new),
        ],
      );
      addTearDown(restarted.dispose);
      final restored = restarted.read(workbenchControllerProvider.notifier);
      await restored.bootstrap();
      await restored.selectWorkspace(
        project: _harness.project,
        workspace: first,
      );
      expect(
        restored.state.workspacePanelFor(first.id).tabKeys,
        firstPanel.tabKeys,
      );
      expect(
        restored.state.workspacePanelFor(first.id).activeKey,
        firstPanel.activeKey,
      );
      expect(
        restored.state.workspacePanelFor(second.id).tabKeys,
        secondPanel.tabKeys,
      );
      expect(_harness.terminalRuntime.closedTabIds, isEmpty);
    },
  );

  test(
    'includes externally created tabs without replacing its primary',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      final external = primary.copyWith(
        id: 'external-tab',
        payload: {'terminalSessionId': 'external-session'},
      );
      await _harness.workbenchRepository.upsertWorkspaceTab(external);
      await _flush();
      final panel = _controller.state.workspacePanelFor(workspace.id);
      expect(panel.primaryTabId, primary.id);
      expect(panel.tabKeys, contains('tab:external-tab'));
      await _controller.selectWorkspaceTab(
        workspaceId: workspace.id,
        tabId: external.id,
      );
      expect(_controller.state.activeWorkspaceTab?.id, external.id);
      expect(_controller.state.viewPrefs.rightSidebarVisible, isTrue);
    },
  );

  test(
    'closing all terminals of a slept workspace does not recreate it',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      await _controller.createTerminalTab(workspace);
      await _controller.sleepWorkspace(workspace);
      await _flush();
      expect(_controller.state.tabsFor(workspace.id), hasLength(2));
      expect(_controller.state.activeWorkspaceId, isNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(2),
      );

      await _controller.closeWorkspaceTabs(
        workspace: workspace,
        tabIds: _controller.state
            .tabsFor(workspace.id)
            .map((tab) => tab.id)
            .toList(),
      );
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
