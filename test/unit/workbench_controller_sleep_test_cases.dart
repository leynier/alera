part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerSleepTests() {
  test(
    'sleep preserves every tab and layout then deselects the workspace',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'notes.txt',
      );
      await _flush();

      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.kind),
        <WorkspaceTabKind>[WorkspaceTabKind.terminal, WorkspaceTabKind.editor],
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);

      await _controller.sleepWorkspace(workspace);
      await _flush();

      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.kind),
        <WorkspaceTabKind>[WorkspaceTabKind.terminal, WorkspaceTabKind.editor],
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);
      expect(_controller.state.activeTabIdByWorkspace[workspace.id], isNotNull);
      expect(_controller.state.activeWorkspace, isNull);
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(2),
      );
    },
  );

  test('sleep drops the per-workspace right sidebar width', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setRightSidebarWidth(360);
    await _flush();
    expect(
      _controller.state.viewPrefs.rightSidebarWidthByWorkspaceId,
      containsPair(workspace.id, 360),
    );

    await _controller.sleepWorkspace(workspace);
    await _flush();

    expect(
      _controller.state.viewPrefs.rightSidebarWidthByWorkspaceId,
      isNot(contains(workspace.id)),
    );
    expect(
      _harness.viewPrefsRepository.prefs.rightSidebarWidthByWorkspaceId,
      isNot(contains(workspace.id)),
    );
  });

  test(
    'sleep preserves a file tab that finishes after the workspace slept',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/late.dart',
      );
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      gate.complete();
      await delayed;
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(
              (tab) =>
                  tab.kind == WorkspaceTabKind.editor &&
                  tab.filePath == 'lib/late.dart',
            ),
        hasLength(1),
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(2),
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
    },
  );

  test('sleep preserves a pull-request tab that finishes after the workspace slept', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final gate = Completer<void>();
    _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
    final delayed = _controller.openGitPullRequestDiffTab(
      workspace: workspace,
      pullRequestNumber: 7,
      commitOid: 'head-7',
      parentOid: 'base-7',
      retentionId: 'retention-late',
    );
    await _flush();
    await _controller.sleepWorkspace(workspace);
    await _flush();
    gate.complete();
    await delayed;
    await _flush();

    expect(
      _controller.state
          .tabsFor(workspace.id)
          .where((tab) => tab.kind == WorkspaceTabKind.gitDiff),
      hasLength(1),
    );
    expect(
      await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      hasLength(2),
    );
    expect(
      _harness.gitBackend.calls.where(
        (call) =>
            call.method == 'releaseHostedReviewRange' &&
            call.args['retentionId'] == 'retention-late',
      ),
      isEmpty,
    );
  });

  test('sleep preserves a preview replacement that finishes after the workspace slept', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    await _flush();
    final gate = Completer<void>();
    _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
    final delayed = _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/b.dart',
      preview: true,
    );
    await _flush();
    await _controller.sleepWorkspace(workspace);
    await _flush();
    gate.complete();
    await delayed;
    await _flush();

    expect(
      _controller.state
          .tabsFor(workspace.id)
          .where(
            (tab) =>
                tab.kind == WorkspaceTabKind.editor &&
                tab.filePath == 'lib/b.dart',
          ),
      hasLength(1),
    );
    expect(
      await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      hasLength(2),
    );
  });

  test(
    'sleep preserves a published pull-request tab even after the watcher lands',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.openGitPullRequestDiffTab(
        workspace: workspace,
        pullRequestNumber: 9,
        commitOid: 'head-9',
        parentOid: 'base-9',
        retentionId: 'retention-watcher',
      );
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      gate.complete();
      await delayed;
      _harness.workbenchRepository.emitTabs(workspace.id);
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where((tab) => tab.kind == WorkspaceTabKind.gitDiff),
        hasLength(1),
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(2),
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
      expect(
        _harness.gitBackend.calls.where(
          (call) =>
              call.method == 'releaseHostedReviewRange' &&
              call.args['retentionId'] == 'retention-watcher',
        ),
        isEmpty,
      );
    },
  );

  test(
    'sleep preserves a late preview promotion that finishes after sleep',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final preview = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _flush();
      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.keepPreviewTab(preview.id);
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      gate.complete();
      await delayed;
      await _flush();

      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        contains(preview.id),
      );
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(2),
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
    },
  );

  test(
    'sleep preserves a dirty preview that is pinned while opening another file',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final preview = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _flush();
      final registry = _harness.container.read(editorSessionRegistryProvider);
      final document = registry.documentFor(preview.id);
      document.loadedText = 'original';
      document.currentText = 'edited';
      expect(registry.isDirty(preview.id), isTrue);

      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        preview: true,
      );
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      gate.complete();
      await delayed;
      await _flush();

      expect(registry.isDirty(preview.id), isTrue);
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(
              (tab) =>
                  tab.kind == WorkspaceTabKind.editor &&
                  tab.filePath == 'lib/b.dart',
            ),
        hasLength(1),
      );
      // The dirty preview is pinned instead of retargeted, so the terminal,
      // a.dart, and b.dart tabs all survive.
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(3),
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
    },
  );

  test(
    'sleep keeps tabs republished by a watcher after a delayed open',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/late.dart',
      );
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      gate.complete();
      _harness.workbenchRepository.emitTabs(workspace.id);
      await delayed;
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(
              (tab) =>
                  tab.kind == WorkspaceTabKind.editor &&
                  tab.filePath == 'lib/late.dart',
            ),
        hasLength(1),
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(2),
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
    },
  );

  test(
    'sleep preserves a delayed persisted tab that wakes the workspace on open',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final original = _controller.state.activeWorkspaceTab!;
      final fork = original.copyWith(id: 'late-fork', title: 'Late fork');
      _harness.workbenchRepository._tabsByWorkspace[workspace
          .id] = <WorkspaceTabRecord>[
        ...await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        fork,
      ];
      final gate = Completer<void>();
      _harness.workbenchRepository.findWorkspaceTabByIdGate = gate;
      final delayed = _controller.openPersistedWorkspaceTab(
        workspaceId: workspace.id,
        tabId: fork.id,
      );
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      gate.complete();
      await delayed;
      await _flush();

      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        contains('late-fork'),
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);
      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        hasLength(2),
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
    },
  );

  test('sleep preserves persisted-tab selection after workspace activation returns', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final original = _controller.state.activeWorkspaceTab!;
    final fork = original.copyWith(id: 'activation-fork', title: 'Fork');
    final tabs = [
      ...await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      fork,
    ];
    _harness.workbenchRepository._tabsByWorkspace[workspace.id] = tabs;
    final other = await _harness.workbenchRepository.upsertWorkspace(
      workspace.copyWith(id: 'other-workspace', name: 'Other'),
    );
    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: other,
    );
    await _flush();
    expect(_controller.state.activeWorkspaceId, other.id);

    final listGate = Completer<void>();
    _harness.workbenchRepository.listWorkspaceTabsGate = listGate;
    final delayed = _controller.openPersistedWorkspaceTab(
      workspaceId: workspace.id,
      tabId: fork.id,
    );
    await _flushUntil(
      () => _harness.workbenchRepository.listWorkspaceTabsGate == null,
    );
    await _controller.sleepWorkspace(workspace);
    await _flush();
    listGate.complete();
    await delayed;
    await _flush();

    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      contains('activation-fork'),
    );
    expect(_controller.state.layoutFor(workspace.id), isNotNull);
    expect(
      _controller.state
          .workspacePanelFor(workspace.id)
          .occupiedKeys
          .contains(WorkspacePanel.tabKey(fork.id)),
      isTrue,
    );
    expect(_controller.state.activeWorkspaceId, isNot(workspace.id));
  });

  test(
    'delayed workspace activation does not overwrite a newer tab selection',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final original = _controller.state.activeWorkspaceTab!;
      final extra = await _controller.createTerminalTab(workspace);
      await _flush();
      final other = await _harness.workbenchRepository.upsertWorkspace(
        workspace.copyWith(id: 'other-activation', name: 'Other'),
      );
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: other,
      );
      await _flush();

      final listGate = Completer<void>();
      _harness.workbenchRepository.listWorkspaceTabsGate = listGate;
      final delayed = _controller.selectWorkspaceTab(
        workspaceId: workspace.id,
        tabId: original.id,
      );
      await _flushUntil(
        () => _harness.workbenchRepository.listWorkspaceTabsGate == null,
      );
      _controller.setActiveTab(workspaceId: workspace.id, tabId: extra.id);
      await _flush();
      listGate.complete();
      await delayed;
      await _flush();

      expect(_controller.state.activeWorkspaceTab?.id, extra.id);
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspacePanel.tabKey(extra.id),
      );
    },
  );
}
