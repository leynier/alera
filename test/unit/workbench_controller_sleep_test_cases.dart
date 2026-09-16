part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerSleepTests() {
  test(
    'sleep removes every tab and layout then deselects the workspace',
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

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.layoutFor(workspace.id), isNull);
      expect(_controller.state.activeTabIdByWorkspace[workspace.id], isNull);
      expect(_controller.state.activeWorkspace, isNull);
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
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
    'sleep discards a file tab that finishes after the workspace was cleared',
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
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.layoutFor(workspace.id), isNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
    },
  );

  test('sleep discards a pull-request tab that finishes after the workspace was cleared', () async {
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
    await expectLater(delayed, throwsStateError);
    await _flush();

    expect(_controller.state.tabsFor(workspace.id), isEmpty);
    expect(
      await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      isEmpty,
    );
    expect(
      _harness.gitBackend.calls.where(
        (call) =>
            call.method == 'releaseHostedReviewRange' &&
            call.args['retentionId'] == 'retention-late',
      ),
      isNotEmpty,
    );
  });

  test(
    'sleep discards a preview replacement that reuses an existing tab id',
    () async {
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
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
    },
  );

  test(
    'sleep discards a published pull-request tab even after the watcher lands',
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
      await expectLater(delayed, throwsStateError);
      _harness.workbenchRepository.emitTabs(workspace.id);
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.layoutFor(workspace.id), isNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
      expect(
        _harness.gitBackend.calls.where(
          (call) =>
              call.method == 'releaseHostedReviewRange' &&
              call.args['retentionId'] == 'retention-watcher',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'sleep discards a late preview promotion that finishes after sleep',
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
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
    },
  );

  test(
    'sleep discards a dirty preview that is pinned while opening another file',
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
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
    },
  );

  test('sleep ignores a watcher publication that lands before delayed-open rollback', () async {
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
    await expectLater(delayed, throwsStateError);
    await _flush();

    expect(_controller.state.tabsFor(workspace.id), isEmpty);
    expect(_controller.state.layoutFor(workspace.id), isNull);
    expect(
      await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      isEmpty,
    );
    expect(
      await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
      isNull,
    );
  });

  test(
    'sleep discards a delayed persisted tab without waking the workspace',
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
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.layoutFor(workspace.id), isNull);
      expect(_controller.state.activeWorkspaceId, isNull);
      expect(
        await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
        isEmpty,
      );
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
    },
  );

  test(
    'sleep ignores persisted-tab selection after workspace activation returns',
    () async {
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

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.layoutFor(workspace.id), isNull);
      expect(
        _controller.state.activeTabIdByWorkspace.containsKey(workspace.id),
        isFalse,
      );
      expect(
        _controller.state
            .workspacePanelFor(workspace.id)
            .occupiedKeys
            .contains(WorkspacePanel.tabKey(fork.id)),
        isFalse,
      );
      expect(_controller.state.activeWorkspaceId, isNot(workspace.id));
    },
  );

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

  test(
    'delayed workspace activation does not overwrite a tool selected while it is pending',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final original = _controller.state.activeWorkspaceTab!;
      await _controller.createTerminalTab(workspace);
      await _flush();
      final other = await _harness.workbenchRepository.upsertWorkspace(
        workspace.copyWith(id: 'other-tool-activation', name: 'Other'),
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
      _controller.setContextPanelTab(WorkbenchContextPanelTab.search);
      await _flush();
      listGate.complete();
      await delayed;
      await _flush();

      expect(_controller.state.activeWorkspaceTab, isNull);
      expect(
        _controller.state.workspacePanelFor(workspace.id).focusedKey,
        WorkspaceTool.search.key,
      );
    },
  );

  test(
    'closing a published pull-request tab discards a delayed retention persist',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final gate = Completer<void>();
      _harness.gitBackend.persistHostedReviewRangeGate = gate;
      final delayed = _controller.openGitPullRequestDiffTab(
        workspace: workspace,
        pullRequestNumber: 11,
        commitOid: 'head-11',
        parentOid: 'base-11',
        retentionId: 'retention-closed',
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
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: published.id,
      );
      await _flush();
      gate.complete();
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == published.id),
        isFalse,
      );
      expect(
        _controller.state
            .workspacePanelFor(workspace.id)
            .occupiedKeys
            .contains(WorkspacePanel.tabKey(published.id)),
        isFalse,
      );
    },
  );

  test(
    'sleep skips close-tab layout persistence after the workspace was cleared',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final extra = await _controller.createTerminalTab(workspace);
      await _flush();
      final closeGate = Completer<void>();
      _harness.workbenchRepository.removeWorkspaceTabGate = closeGate;
      final closing = _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: extra.id,
      );
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      closeGate.complete();
      await closing;
      await _flush();

      expect(_controller.state.tabsFor(workspace.id), isEmpty);
      expect(_controller.state.layoutFor(workspace.id), isNull);
      expect(
        await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNull,
      );
    },
  );

  test('sleep rejects a queued file open requested before the workspace was cleared', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final firstGate = Completer<void>();
    _harness.workbenchRepository.upsertWorkspaceTabGate = firstGate;
    final first = _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/first.dart',
    );
    await _flush();
    final second = _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/second.dart',
    );
    await _controller.sleepWorkspace(workspace);
    await _flush();
    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    await _flush();
    firstGate.complete();
    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    await _flush();

    expect(
      _controller.state
          .tabsFor(workspace.id)
          .where((tab) => tab.kind == WorkspaceTabKind.editor),
      isEmpty,
    );
  });

  test(
    'closing a pending automatic primary still creates a replacement',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/keep.dart',
      );
      await _flush();
      final releaseGate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabReleaseGate = releaseGate;
      final closing = _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: primary.id,
      );
      await _flushUntil(
        () =>
            _harness.workbenchRepository.upsertWorkspaceTabReleaseGate == null,
      );
      await closing;
      await _flushUntil(
        () => _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id != primary.id && isPrimaryTerminalCandidate(tab)),
      );
      final pendingId = _controller.state
          .tabsFor(workspace.id)
          .firstWhere(
            (tab) => tab.id != primary.id && isPrimaryTerminalCandidate(tab),
          )
          .id;
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: pendingId,
      );
      await _flush();
      releaseGate.complete();
      await _flushUntil(
        () => _controller.state
            .tabsFor(workspace.id)
            .any(
              (tab) => tab.id != pendingId && isPrimaryTerminalCandidate(tab),
            ),
      );

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == pendingId),
        isFalse,
      );
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
        hasLength(1),
      );
    },
  );

  test(
    'sleeping during a pending primary list still creates a replacement',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      expect(
        _controller.state.tabsFor(workspace.id).where(isPrimaryTerminalCandidate),
        hasLength(1),
      );
      final other = await _harness.workbenchRepository.upsertWorkspace(
        workspace.copyWith(id: 'other-primary-list', name: 'Other'),
      );
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: other,
      );
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();
      expect(_controller.state.tabsFor(workspace.id), isEmpty);

      final listGate = Completer<void>();
      _harness.workbenchRepository.listWorkspaceTabsGate = listGate;
      final delayed = _controller.selectWorkspace(
        project: _harness.project,
        workspace: workspace,
      );
      await _flushUntil(
        () => _harness.workbenchRepository.listWorkspaceTabsGate == null,
      );
      await _controller.sleepWorkspace(workspace);
      await _flush();
      final reselect = _controller.selectWorkspace(
        project: _harness.project,
        workspace: workspace,
      );
      await _flush();
      listGate.complete();
      await delayed;
      await reselect;
      await _flushUntil(
        () => _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate)
            .length ==
        1,
      );

      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        _controller.state.tabsFor(workspace.id).where(isPrimaryTerminalCandidate),
        hasLength(1),
      );
    },
  );

  test(
    'a failed automatic primary creation does not retry indefinitely',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/keep.dart',
      );
      await _flush();
      final beforeCreates = _harness.workbenchRepository.upsertWorkspaceTabCalls;
      _harness.workbenchRepository.upsertWorkspaceTabError = StateError(
        'cannot create terminal',
      );
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: primary.id,
      );
      await _flush();
      await _flush();
      final afterCreates = _harness.workbenchRepository.upsertWorkspaceTabCalls;
      _harness.workbenchRepository.upsertWorkspaceTabError = null;

      expect(afterCreates - beforeCreates, 1);
      expect(
        _controller.state.error,
        contains('cannot create terminal'),
      );
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
        isEmpty,
      );
    },
  );

  test(
    'selecting a slept workspace creates one primary without restoring width',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      _controller.setRightSidebarWidth(360);
      await _flush();
      await _controller.sleepWorkspace(workspace);
      await _flush();

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: workspace,
      );
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
        hasLength(1),
      );
      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        _controller.state.viewPrefs.rightSidebarWidthByWorkspaceId,
        isNot(contains(workspace.id)),
      );
    },
  );
}
