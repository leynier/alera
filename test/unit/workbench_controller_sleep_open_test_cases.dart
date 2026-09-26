part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerSleepOpenTests() {
  test('delayed workspace activation does not overwrite a tool selected while it is pending', () async {
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
  });

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

  test('sleep preserves remaining tabs when a close finishes after the workspace slept', () async {
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

    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      isNot(contains(extra.id)),
    );
    expect(_controller.state.tabsFor(workspace.id), isNotEmpty);
    expect(_controller.state.layoutFor(workspace.id), isNotNull);
    expect(
      await _harness.workbenchRepository.findWorkbenchLayout(workspace.id),
      isNotNull,
    );
  });

  test(
    'sleep preserves queued file opens requested before the workspace slept',
    () async {
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
      await first;
      await second;
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where((tab) => tab.kind == WorkspaceTabKind.editor),
        hasLength(2),
      );
    },
  );

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
            .any(
              (tab) => tab.id != primary.id && isPrimaryTerminalCandidate(tab),
            ),
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
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
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
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
        hasLength(1),
      );

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
        () =>
            _controller.state
                .tabsFor(workspace.id)
                .where(isPrimaryTerminalCandidate)
                .length ==
            1,
      );

      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
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
      final beforeCreates =
          _harness.workbenchRepository.upsertWorkspaceTabCalls;
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
      expect(_controller.state.error, contains('cannot create terminal'));
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
        isEmpty,
      );
    },
  );

  test('selecting a slept workspace shows its preserved tabs without restoring width', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _controller.setRightSidebarWidth(360);
    await _flush();
    await _controller.sleepWorkspace(workspace);
    await _flush();
    expect(
      _controller.state.tabsFor(workspace.id).where(isPrimaryTerminalCandidate),
      hasLength(1),
    );

    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    await _flush();

    expect(
      _controller.state.tabsFor(workspace.id).where(isPrimaryTerminalCandidate),
      hasLength(1),
    );
    expect(_controller.state.activeWorkspaceId, workspace.id);
    expect(
      _controller.state.viewPrefs.rightSidebarWidthByWorkspaceId,
      isNot(contains(workspace.id)),
    );
  });

  test('sleep shows its terminals as closed right away', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'notes.txt',
    );
    await _flush();
    final terminalId = _controller.state
        .tabsFor(workspace.id)
        .firstWhere((tab) => tab.kind == WorkspaceTabKind.terminal)
        .id;

    await _controller.sleepWorkspace(workspace);
    await _flush();

    expect(_controller.state.sleptTabIdsByWorkspaceId[workspace.id], <String>[
      terminalId,
    ]);
    expect(
      _controller.state.awakeTabsFor(workspace.id).map((tab) => tab.kind),
      <WorkspaceTabKind>[WorkspaceTabKind.editor],
    );
  });
}
