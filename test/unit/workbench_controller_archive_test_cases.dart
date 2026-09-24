part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerArchiveTests() {
  test(
    'archive flags the workspace, closes sessions, and preserves tabs',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'notes.txt',
      );
      await _flush();

      await _controller.archiveWorkspace(workspace);
      await _flush();

      final archived = _controller.state
          .workspacesFor(workspace.projectId)
          .firstWhere((candidate) => candidate.id == workspace.id);
      expect(archived.isArchived, isTrue);
      // The archived workspace leaves the selection while its tabs survive for
      // resume through their stored native session ids.
      expect(_controller.state.activeWorkspaceId, isNull);
      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.kind),
        <WorkspaceTabKind>[WorkspaceTabKind.terminal, WorkspaceTabKind.editor],
      );
      expect(_controller.state.layoutFor(workspace.id), isNotNull);
      expect(
        _harness.terminalRuntime.closedWorkspaceIds,
        contains(workspace.id),
      );
      expect(_controller.state.error, isNull);
    },
  );

  test('unarchive clears the flag and keeps tabs', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.archiveWorkspace(workspace);
    await _flush();
    expect(_controller.state.activeWorkspaceId, isNull);

    final archived = _controller.state
        .workspacesFor(workspace.projectId)
        .firstWhere((candidate) => candidate.id == workspace.id);
    await _controller.unarchiveWorkspace(archived);
    await _flush();

    final restored = _controller.state
        .workspacesFor(workspace.projectId)
        .firstWhere((candidate) => candidate.id == workspace.id);
    expect(restored.isArchived, isFalse);
    expect(_controller.state.tabsFor(workspace.id), isNotEmpty);
    expect(_controller.state.error, isNull);
  });

  test('surfaces archive failures without changing state', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    _harness.workbenchRepository.upsertWorkspaceError = StateError(
      'archive failed',
    );

    await expectLater(
      _controller.archiveWorkspace(workspace),
      throwsStateError,
    );

    expect(_controller.state.activeWorkspace?.isArchived, isFalse);
    expect(_controller.state.error, contains('archive failed'));
  });

  test('archived workspaces hide unless the view option is enabled', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.archiveWorkspace(workspace);
    await _flush();

    expect(
      workspaceOrderOfRows(buildSidebarRows(_controller.state)),
      isNot(contains(workspace.id)),
    );

    _controller.setShowArchivedWorkspaces(true);
    expect(
      workspaceOrderOfRows(buildSidebarRows(_controller.state)),
      contains(workspace.id),
    );
    expect(_controller.state.viewPrefs.showArchivedWorkspaces, isTrue);
  });

  test('sleep preserves tabs while closing the workspace sessions', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _flush();

    await _controller.sleepWorkspace(workspace);
    await _flush();

    expect(_controller.state.tabsFor(workspace.id), isNotEmpty);
    expect(_controller.state.layoutFor(workspace.id), isNotNull);
    expect(_controller.state.activeWorkspaceId, isNull);
    expect(_harness.terminalRuntime.closedWorkspaceIds, contains(workspace.id));
    expect(
      await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      isNotEmpty,
    );
  });
}
