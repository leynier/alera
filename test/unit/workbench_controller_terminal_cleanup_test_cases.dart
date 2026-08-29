part of 'workbench_controller_test.dart';

/// Closing or losing a tab must free its live terminal handle and editor
/// document, or the xterm scrollback buffer stays reachable for the rest of
/// the session. These cases pin the centralized cleanup in the controller so
/// no close path can forget it again.
void _registerWorkbenchControllerTerminalCleanupTests() {
  test('closing a tab disposes its live terminal handle', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final tab = _controller.state.activeWorkspaceTab!;
    _harness.terminalRuntime.sessionFor(workspace: workspace, tab: tab);
    expect(_harness.terminalRuntime.sessions, isNotEmpty);

    await _controller.closeWorkspaceTab(workspace: workspace, tabId: tab.id);
    await _flush();

    expect(_harness.terminalRuntime.closedTabIds, contains(tab.id));
    expect(_harness.terminalRuntime.sessions, isEmpty);
  });

  test('closing a tab forgets its editor document', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final tab = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'docs/readme.md',
    );
    await _flush();
    final registry = _harness.container.read(editorSessionRegistryProvider);
    registry.documentFor(tab.id)
      ..acceptLoaded(
        native_files.WorkspaceEditorTextFile(
          rawContent: 'original',
          displayContent: 'original',
          contentToken: 'token-1',
          modifiedMillis: 0,
          size: BigInt.zero,
        ),
      )
      ..updateCurrentText('edited');
    expect(registry.isDirty(tab.id), isTrue);

    await _controller.closeWorkspaceTab(workspace: workspace, tabId: tab.id);
    await _flush();

    expect(registry.isDirty(tab.id), isFalse);
  });

  test('watched tab removal releases the terminal handle', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final tab = _controller.state.activeWorkspaceTab!;
    _harness.terminalRuntime.sessionFor(workspace: workspace, tab: tab);

    await _harness.workbenchRepository.removeWorkspaceTab(tab.id);
    await _flushUntil(() => _controller.state.tabsFor(workspace.id).isEmpty);

    expect(_harness.terminalRuntime.releasedTabIds, contains(tab.id));
    expect(_harness.terminalRuntime.sessions, isEmpty);
    // Released, not closed: the record disappeared from persisted state, so
    // the PTY may still belong to whichever client removed it.
    expect(_harness.terminalRuntime.closedTabIds, isNot(contains(tab.id)));
  });

  test(
    'workspace removal retires the keepAlive search state for its id',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final container = _harness.container;
      container
          .read(workspaceSearchControllerProvider(workspace.id).notifier)
          .toggleViewAsTree();
      expect(
        container
            .read(workspaceSearchControllerProvider(workspace.id))
            .viewAsTree,
        isTrue,
      );

      await _harness.workbenchRepository.removeWorkspace(workspace.id);
      await _flushUntil(
        () => _controller.state.workspacesFor(_harness.project.id).isEmpty,
      );
      await _flush();

      // A fresh default state proves the retired instance was disposed rather
      // than kept alive for the rest of the session.
      expect(
        container
            .read(workspaceSearchControllerProvider(workspace.id))
            .viewAsTree,
        isFalse,
      );
    },
  );

  test('watched workspace removal releases its terminal handles', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final tab = _controller.state.activeWorkspaceTab!;
    _harness.terminalRuntime.sessionFor(workspace: workspace, tab: tab);

    await _harness.workbenchRepository.removeWorkspace(workspace.id);
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isEmpty,
    );

    expect(
      _harness.terminalRuntime.releasedWorkspaceIds,
      contains(workspace.id),
    );
    expect(_harness.terminalRuntime.sessions, isEmpty);
  });
}
