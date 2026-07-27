part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerCreateWorkspaceTests() {
  test(
    'createWorkspace surfaces service failures in state and rethrows',
    () async {
      _harness.gitBackend.failingWorktreeAddBranches.add('feature/broken');

      await expectLater(
        _controller.createWorkspace(
          project: _harness.project,
          sourceBranch: 'main',
          newBranchName: 'feature/broken',
        ),
        throwsA(isA<Exception>()),
      );

      expect(_controller.state.error, isNotNull);
      expect(
        _controller.state
            .workspacesFor(_harness.project.id)
            .where((workspace) => workspace.branch == 'feature/broken'),
        isEmpty,
      );
    },
  );

  test('createWorkspace ignores a blank parent workspace id', () async {
    final result = await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/no-parent',
      parentWorkspaceId: '   ',
    );

    expect(result.hasParentLinkError, isFalse);
    expect(_harness.workspaceGraphRepository.linkedWorkspaces, isEmpty);
    expect(_controller.state.activeWorkspaceId, result.workspace.id);
  });

  test(
    'createWorkspace selects the workspace before its watcher catches up',
    () async {
      await _harness.dispose();
      _harness = _WorkbenchHarness(
        const _ManagedWorkspaceRuntimeWithoutWatcher(),
      );
      _controller = _harness._controller;
      await _controller.bootstrap();
      await _flushUntil(
        () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
      );

      final result = await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/delayed-workspace-event',
      );

      expect(_controller.state.activeProjectId, _harness.project.id);
      expect(_controller.state.activeWorkspace, result.workspace);
      expect(_controller.state.activeWorkspaceTab?.title, 'Terminal 1');
      expect(_controller.state.activeLayout?.workspaceId, result.workspace.id);

      await _harness.workbenchRepository.upsertWorkspace(result.workspace);
      await _flush();

      expect(_controller.state.activeWorkspace, result.workspace);
      expect(_controller.state.activeWorkspaceTab?.title, 'Terminal 1');
    },
  );

  test('createWorkspace clears a previous error on success', () async {
    _harness.gitBackend.failingWorktreeAddBranches.add('feature/first-try');
    await expectLater(
      _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/first-try',
      ),
      throwsA(isA<Exception>()),
    );
    expect(_controller.state.error, isNotNull);

    final result = await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/second-try',
    );

    expect(result.workspace.branch, 'feature/second-try');
    expect(_controller.state.error, isNull);
  });
}

class _ManagedWorkspaceRuntimeWithoutWatcher
    implements ManagedWorkspaceRuntime {
  const _ManagedWorkspaceRuntimeWithoutWatcher();

  @override
  Future<WorkspaceCreationResult> createLinkedWorkspace({
    required Project project,
    required String sourceBranch,
    required String newBranchName,
    required bool reuseExistingBranch,
    String? name,
  }) async {
    final now = DateTime.utc(2026, 5, 22, 2);
    return WorkspaceCreationResult(
      workspace: Workspace(
        id: 'workspace-with-delayed-event',
        projectId: project.id,
        name: name ?? newBranchName,
        branch: newBranchName,
        path: p.join(project.repoPath, 'delayed-workspace'),
        createdAt: now,
        updatedAt: now,
        kind: WorkspaceKind.linked,
        status: WorkspaceStatus.active,
        sourceBranch: reuseExistingBranch ? null : sourceBranch,
        reusesExistingBranch: reuseExistingBranch,
      ),
      setupReport: WorktreeSetupReport.empty,
    );
  }

  @override
  Future<void> removeWorkspace({
    required Workspace workspace,
    bool? deleteBranch,
  }) async {}
}
