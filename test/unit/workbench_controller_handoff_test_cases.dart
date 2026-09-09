part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerHandoffTests() {
  test('host initiated hand on retains the live dirty document and terminal handle', () async {
    await _harness.dispose();
    final runtime = _HandoffManagedWorkspaceRuntime();
    _harness = _WorkbenchHarness(runtime);
    _controller = _harness._controller;
    await _controller.bootstrap();
    final main = await _selectMainWorkspace(_controller, _harness);
    final child = (await _controller.handOffWorkspace(
      workspace: main,
      branch: 'feat/live',
    )).workspace;
    final terminal = _controller.state.tabsFor(child.id).first;
    final handle = _harness.terminalRuntime.sessionFor(
      workspace: child,
      tab: terminal,
    );
    final editor = await _controller.openEditorTab(
      workspace: child,
      relativePath: 'notes.txt',
    );
    final registry = _harness.container.read(editorSessionRegistryProvider);
    final document = registry.documentFor(editor.id)
      ..attachFile(workspacePath: child.path, relativePath: 'notes.txt')
      ..acceptLoaded(
        native_files.WorkspaceEditorTextFile(
          rawContent: 'disk',
          displayContent: 'disk',
          contentToken: 'original-token',
          modifiedMillis: 0,
          size: .zero,
        ),
      )
      ..updateCurrentText('not saved');
    await runtime.persistTransfer(child, main, removeSource: true);
    await _flushUntil(
      () =>
          _controller.state
              .tabsFor(main.id)
              .any((tab) => tab.id == editor.id) &&
          document.workspacePath == main.path,
    );
    expect(document.currentText, 'not saved');
    expect(document.contentToken, 'original-token');
    expect(
      identical(_harness.terminalRuntime.peekSession(terminal.id), handle),
      isTrue,
    );
    expect(handle.workspaceId, main.id);
    expect(_harness.terminalRuntime.closedWorkspaceIds, isEmpty);
  });

  test(
    'hand on refuses unsaved main editors before the runtime call',
    () async {
      await _harness.dispose();
      final runtime = _HandoffManagedWorkspaceRuntime();
      _harness = _WorkbenchHarness(runtime);
      _controller = _harness._controller;
      await _controller.bootstrap();
      final main = await _selectMainWorkspace(_controller, _harness);
      final child = (await _controller.handOffWorkspace(
        workspace: main,
        branch: 'feat/live',
      )).workspace;
      final editor = await _controller.openEditorTab(
        workspace: main,
        relativePath: 'notes.txt',
      );
      final document =
          _harness.container
              .read(editorSessionRegistryProvider)
              .documentFor(editor.id)
            ..attachFile(workspacePath: main.path, relativePath: 'notes.txt')
            ..acceptLoaded(
              native_files.WorkspaceEditorTextFile(
                rawContent: 'disk',
                displayContent: 'disk',
                contentToken: 'token',
                modifiedMillis: 0,
                size: .zero,
              ),
            )
            ..updateCurrentText('main edit');
      await expectLater(
        _controller.handOnWorkspace(
          project: _harness.project,
          workspace: child,
        ),
        throwsStateError,
      );
      expect(runtime.handOnWorkspaceId, isNull);
      expect(document.currentText, 'main edit');
    },
  );

  test('handOffWorkspace selects the new child workspace', () async {
    await _harness.dispose();
    final runtime = _HandoffManagedWorkspaceRuntime();
    _harness = _WorkbenchHarness(runtime);
    _controller = _harness._controller;
    await _controller.bootstrap();
    final main = await _selectMainWorkspace(_controller, _harness);
    final terminal = _controller.state.activeWorkspaceTab!;
    final handle = _harness.terminalRuntime.sessionFor(
      workspace: main,
      tab: terminal,
    );
    final editor = await _controller.openEditorTab(
      workspace: main,
      relativePath: 'tracked.txt',
    );
    final registry = _harness.container.read(editorSessionRegistryProvider);
    final document = registry.documentFor(editor.id)
      ..attachFile(workspacePath: main.path, relativePath: 'tracked.txt')
      ..acceptLoaded(
        native_files.WorkspaceEditorTextFile(
          rawContent: 'disk',
          displayContent: 'disk',
          contentToken: 'token',
          modifiedMillis: 0,
          size: .zero,
        ),
      )
      ..updateCurrentText('unsaved buffer');

    final result = await _controller.handOffWorkspace(
      workspace: main,
      branch: 'feat/controller',
      name: 'Controller Child',
    );

    expect(result.workspace.branch, 'feat/controller');
    expect(_controller.state.activeWorkspaceId, result.workspace.id);
    expect(runtime.handOffWorkspaceId, main.id);
    expect(runtime.handOffBranch, 'feat/controller');
    await _flush();
    expect(
      identical(_harness.terminalRuntime.peekSession(terminal.id), handle),
      isTrue,
    );
    expect(handle.workspaceId, result.workspace.id);
    expect(identical(registry.documentFor(editor.id), document), isTrue);
    expect(document.workspacePath, result.workspace.path);
    expect(document.currentText, 'unsaved buffer');
    expect(document.contentToken, 'token');
    expect(_controller.state.tabsFor(main.id), isEmpty);
    expect(
      _controller.state.tabsFor(result.workspace.id).map((tab) => tab.id),
      containsAll([terminal.id, editor.id]),
    );
    expect(
      _controller.state.activeTabIdByWorkspace[result.workspace.id],
      editor.id,
    );
  });

  test('handOnWorkspace selects main after removing the child', () async {
    await _harness.dispose();
    final runtime = _HandoffManagedWorkspaceRuntime();
    _harness = _WorkbenchHarness(runtime);
    _controller = _harness._controller;
    await _controller.bootstrap();
    await _selectMainWorkspace(_controller, _harness);
    final child = Workspace(
      id: 'child',
      projectId: _harness.project.id,
      name: 'Child',
      branch: 'feat/back',
      path: p.join(_harness.tempDir.path, 'child'),
      createdAt: DateTime.utc(2026, 5, 22, 2),
      updatedAt: DateTime.utc(2026, 5, 22, 2),
      kind: .linked,
      status: .active,
    );
    await _harness.workbenchRepository.upsertWorkspace(child);
    await _flushUntil(
      () => _controller.state
          .workspacesFor(_harness.project.id)
          .any((workspace) => workspace.id == child.id),
    );

    final main = await _controller.handOnWorkspace(
      project: _harness.project,
      workspace: child,
    );

    expect(main.isMain, isTrue);
    expect(main.branch, 'feat/back');
    expect(_controller.state.activeWorkspaceId, main.id);
    expect(runtime.handOnWorkspaceId, child.id);
    expect(
      _harness.terminalRuntime.closedWorkspaceIds,
      isNot(contains(child.id)),
    );
  });
}

class _HandoffManagedWorkspaceRuntime implements ManagedWorkspaceRuntime {
  String? handOffWorkspaceId;
  String? handOffBranch;
  String? handOnWorkspaceId;

  Future<void> persistTransfer(
    Workspace source,
    Workspace destination, {
    bool removeSource = false,
  }) async {
    final repository = _harness.workbenchRepository;
    await repository.upsertWorkspace(destination);
    final tabs = await repository.listWorkspaceTabs(source.id);
    for (final tab in tabs) {
      await repository.upsertWorkspaceTab(
        tab.copyWith(workspaceId: destination.id),
      );
    }
    final layout = await repository.findWorkbenchLayout(source.id);
    if (layout != null) {
      await repository.upsertWorkbenchLayout(
        layout.copyWith(workspaceId: destination.id),
      );
      await repository.removeWorkbenchLayout(source.id);
    }
    if (removeSource) {
      await repository.removeWorkspace(source.id, cascadeTabs: false);
    }
  }

  @override
  Future<WorkspaceCreationResult> createLinkedWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    String? name,
    String? hostId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeWorkspace({
    required Workspace workspace,
    bool? deleteBranch,
    String? activeWorkspaceId,
  }) async {}

  @override
  Future<WorkspaceCreationResult> handOffWorkspace({
    required Workspace workspace,
    required String branch,
    required bool reuseExistingBranch,
    String? name,
  }) async {
    handOffWorkspaceId = workspace.id;
    handOffBranch = branch;
    final now = DateTime.utc(2026, 5, 22, 4);
    final result = WorkspaceCreationResult(
      workspace: Workspace(
        id: 'child-from-hand-off',
        projectId: workspace.projectId,
        name: name ?? branch,
        branch: branch,
        path: p.join(workspace.path, 'child'),
        createdAt: now,
        updatedAt: now,
        kind: .linked,
        status: .active,
        parentWorkspaceId: workspace.id,
      ),
      setupReport: .empty,
    );
    await persistTransfer(workspace, result.workspace);
    return result;
  }

  @override
  Future<WorkspaceHandOnResult> handOnWorkspace({
    required Workspace workspace,
    String? activeWorkspaceId,
  }) async {
    handOnWorkspaceId = workspace.id;
    final now = DateTime.utc(2026, 5, 22, 5);
    final main = _controller.state
        .workspacesFor(workspace.projectId)
        .firstWhere((candidate) => candidate.isMain);
    final result = WorkspaceHandOnResult(
      workspace: main.copyWith(branch: workspace.branch, updatedAt: now),
      removedWorkspaceId: workspace.id,
    );
    await persistTransfer(workspace, result.workspace, removeSource: true);
    return result;
  }
}
