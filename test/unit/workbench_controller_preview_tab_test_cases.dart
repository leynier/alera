part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerPreviewTabTests() {
  test('opening another explorer file replaces the preview tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final first = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    final second = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/b.dart',
      preview: true,
    );
    await _flush();

    expect(second.id, first.id);
    expect(second.filePath, 'lib/b.dart');
    expect(second.isPreview, isTrue);
    expect(
      _controller.state.tabsFor(workspace.id).where(_isFileTab),
      hasLength(1),
    );
    expect(_controller.state.activeWorkspaceTab?.id, first.id);
  });

  test(
    'keeping a preview tab then opening another file creates a second tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final first = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _controller.keepPreviewTab(first.id);
      final second = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        preview: true,
      );
      await _flush();

      final kept = _controller.state
          .tabsFor(workspace.id)
          .firstWhere((tab) => tab.id == first.id);
      expect(kept.isPreview, isFalse);
      expect(second.id, isNot(first.id));
      expect(second.isPreview, isTrue);
      expect(
        _controller.state.tabsFor(workspace.id).where(_isFileTab),
        hasLength(2),
      );
    },
  );

  test('reopening the same preview path reuses the existing tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final first = await _controller.openFileTab(
      workspace: workspace,
      relativePath: './lib/a.dart',
      preview: true,
    );
    final second = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    await _flush();

    expect(second.id, first.id);
    expect(second.isPreview, isTrue);
    expect(
      _controller.state.tabsFor(workspace.id).where(_isFileTab),
      hasLength(1),
    );
  });

  test('permanent open of a preview path pins that tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final preview = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    final pinned = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
    );
    await _flush();

    expect(pinned.id, preview.id);
    expect(pinned.isPreview, isFalse);
    expect(
      _controller.state.tabsFor(workspace.id).singleWhere(_isFileTab).isPreview,
      isFalse,
    );
  });

  test('split panes still share one preview slot', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final previewA = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    await _flush();
    final originalGroupId = _controller.state
        .workspacePanelFor(workspace.id)
        .ensuredLayout(workspace.id)
        .groupIdForTab(WorkspacePanel.tabKey(previewA.id))!;
    await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: originalGroupId,
      zone: .right,
    );
    await _flush();

    final previewB = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/b.dart',
      preview: true,
    );
    await _flush();

    expect(previewB.id, previewA.id);
    expect(previewB.filePath, 'lib/b.dart');
    expect(
      _controller.state.tabsFor(workspace.id).where(_isFileTab),
      hasLength(1),
    );
  });

  test(
    'closing a preview during replacement discards the late upsert',
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
      final delayed = _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        preview: true,
      );
      await _flush();
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: preview.id,
      );
      await _flush();
      gate.complete();
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == preview.id),
        isFalse,
      );
      expect(
        await _harness.workbenchRepository.findWorkspaceTabById(preview.id),
        isNull,
      );
      expect(
        _controller.state
            .workspacePanelFor(workspace.id)
            .occupiedKeys
            .contains(WorkspacePanel.tabKey(preview.id)),
        isFalse,
      );
    },
  );

  test(
    'a failed close does not discard a later reopen of the same file',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final preview = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/keep.dart',
        preview: true,
      );
      await _flush();
      _harness.workbenchRepository.removeWorkspaceTabError = StateError(
        'close failed',
      );
      await expectLater(
        _controller.closeWorkspaceTab(workspace: workspace, tabId: preview.id),
        throwsStateError,
      );
      _harness.workbenchRepository.removeWorkspaceTabError = null;
      await _flush();

      final reopened = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/keep.dart',
        preview: true,
      );
      await _flush();

      expect(reopened.id, preview.id);
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == preview.id),
        isTrue,
      );
    },
  );

  test('a partial bulk close does not discard a later reopen of the unattempted tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final first = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/keep.dart',
      preview: true,
    );
    final second = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/fail.dart',
    );
    final third = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/drop.dart',
    );
    await _flush();
    _harness.workbenchRepository.removeWorkspaceTabErrorsById[second.id] =
        StateError('close failed');
    await expectLater(
      _controller.closeWorkspaceTabs(
        workspace: workspace,
        tabIds: <String>[first.id, second.id, third.id],
      ),
      throwsStateError,
    );
    _harness.workbenchRepository.removeWorkspaceTabErrorsById.clear();
    await _flush();

    final reopened = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/drop.dart',
    );
    await _flush();

    expect(reopened.id, third.id);
    expect(
      _controller.state.tabsFor(workspace.id).any((tab) => tab.id == third.id),
      isTrue,
    );
    expect(
      _controller.state.tabsFor(workspace.id).any((tab) => tab.id == first.id),
      isFalse,
    );
  });

  test(
    'a partial bulk close finalizes successful closes and keeps remaining tabs',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final primary = _controller.state.activeWorkspaceTab!;
      final failing = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/fail.dart',
      );
      final remaining = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/keep.dart',
      );
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: remaining.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: primary.id);
      await _flush();
      _harness.workbenchRepository.removeWorkspaceTabErrorsById[failing.id] =
          StateError('close failed');
      await expectLater(
        _controller.closeWorkspaceTabs(
          workspace: workspace,
          tabIds: <String>[primary.id, failing.id, remaining.id],
        ),
        throwsStateError,
      );
      _harness.workbenchRepository.removeWorkspaceTabErrorsById.clear();
      await _flush();
      await _flushUntil(
        () => _controller.state
            .tabsFor(workspace.id)
            .any(isPrimaryTerminalCandidate),
      );

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == primary.id),
        isFalse,
      );
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == failing.id),
        isTrue,
      );
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == remaining.id),
        isTrue,
      );
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where(isPrimaryTerminalCandidate),
        hasLength(1),
      );
      expect(_controller.state.activeWorkspaceTab?.id, remaining.id);
    },
  );

  test(
    'a partial bulk close restores MRU among surviving requested tabs',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final a = _controller.state.activeWorkspaceTab!;
      final b = await _controller.createTerminalTab(workspace);
      final c = await _controller.createTerminalTab(workspace);
      final d = await _controller.createTerminalTab(workspace);
      await _flush();
      _controller.setActiveTab(workspaceId: workspace.id, tabId: d.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: c.id);
      _controller.setActiveTab(workspaceId: workspace.id, tabId: a.id);
      await _flush();
      _harness.workbenchRepository.removeWorkspaceTabErrorsById[b.id] =
          StateError('close failed');
      await expectLater(
        _controller.closeWorkspaceTabs(
          workspace: workspace,
          tabIds: <String>[a.id, b.id, c.id],
        ),
        throwsStateError,
      );
      _harness.workbenchRepository.removeWorkspaceTabErrorsById.clear();
      await _flush();

      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        containsAll(<String>[b.id, c.id, d.id]),
      );
      expect(
        _controller.state.tabsFor(workspace.id).any((tab) => tab.id == a.id),
        isFalse,
      );
      expect(_controller.state.activeWorkspaceTab?.id, c.id);
    },
  );

  test(
    'closing a preview during keepPreviewTab discards the late promotion',
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
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: preview.id,
      );
      await _flush();
      gate.complete();
      await expectLater(delayed, throwsStateError);
      await _flush();

      expect(
        _controller.state
            .tabsFor(workspace.id)
            .any((tab) => tab.id == preview.id),
        isFalse,
      );
      expect(
        await _harness.workbenchRepository.findWorkspaceTabById(preview.id),
        isNull,
      );
    },
  );
}

bool _isFileTab(WorkspaceTabRecord tab) {
  return tab.kind == WorkspaceTabKind.editor ||
      tab.kind == WorkspaceTabKind.markdownViewer ||
      tab.kind == WorkspaceTabKind.pdf;
}

bool _isPreviewSlotTab(WorkspaceTabRecord tab) => tab.isFilePreviewSlot;
