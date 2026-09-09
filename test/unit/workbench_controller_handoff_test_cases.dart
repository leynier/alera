part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerHandoffTests() {
  test('handOffWorkspace selects the new child workspace', () async {
    await _harness.dispose();
    final runtime = _HandoffManagedWorkspaceRuntime();
    _harness = _WorkbenchHarness(runtime);
    _controller = _harness._controller;
    await _controller.bootstrap();
    final main = await _selectMainWorkspace(_controller, _harness);

    final result = await _controller.handOffWorkspace(
      workspace: main,
      branch: 'feat/controller',
      name: 'Controller Child',
    );

    expect(result.workspace.branch, 'feat/controller');
    expect(_controller.state.activeWorkspaceId, result.workspace.id);
    expect(runtime.handOffWorkspaceId, main.id);
    expect(runtime.handOffBranch, 'feat/controller');
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
    expect(_harness.terminalRuntime.closedWorkspaceIds, contains(child.id));
  });
}

class _HandoffManagedWorkspaceRuntime implements ManagedWorkspaceRuntime {
  String? handOffWorkspaceId;
  String? handOffBranch;
  String? handOnWorkspaceId;

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
    return WorkspaceCreationResult(
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
    return WorkspaceHandOnResult(
      workspace: main.copyWith(branch: workspace.branch, updatedAt: now),
      removedWorkspaceId: workspace.id,
    );
  }
}
