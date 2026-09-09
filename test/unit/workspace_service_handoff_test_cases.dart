part of 'workspace_service_test.dart';

void _registerWorkspaceServiceHandoffTests() {
  test(
    'handOffWorkspace requires the main worktree and a host runtime',
    () async {
      final main = await service.ensureMainWorkspace(project);
      await expectLater(
        service.handOffWorkspace(workspace: main, branch: 'feat/x'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('managed workspace runtime'),
          ),
        ),
      );

      final child = main.copyWith(id: 'child', kind: .linked);
      await expectLater(
        service.handOffWorkspace(workspace: child, branch: 'feat/x'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('main worktree'),
          ),
        ),
      );
    },
  );

  test(
    'handOnWorkspace requires a child worktree and a host runtime',
    () async {
      final main = await service.ensureMainWorkspace(project);
      await expectLater(
        service.handOnWorkspace(workspace: main),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('child worktree'),
          ),
        ),
      );

      final child = main.copyWith(id: 'child', kind: .linked);
      await expectLater(
        service.handOnWorkspace(workspace: child),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('managed workspace runtime'),
          ),
        ),
      );
    },
  );

  test('handOffWorkspace delegates to the managed runtime', () async {
    final runtime = _RecordingManagedWorkspaceRuntime();
    service = WorkspaceService(
      repository: repository,
      projectService: ProjectService(gitBackend),
      gitBackend: gitBackend,
      workspaceRoot: WorkspaceRoot(
        override: p.join(tempDir.path, 'workspaces'),
      ),
      managedRuntime: runtime,
      now: () => DateTime.utc(2026, 5, 20, 12),
    );
    final main = await service.ensureMainWorkspace(project);

    final result = await service.handOffWorkspace(
      workspace: main,
      branch: 'feat/host',
      name: 'Hosted',
    );

    expect(result.workspace.branch, 'feat/host');
    expect(runtime.handOffBranch, 'feat/host');
    expect(runtime.handOffName, 'Hosted');
    expect(runtime.handOffReuse, isFalse);
  });

  test('handOnWorkspace delegates to the managed runtime', () async {
    final runtime = _RecordingManagedWorkspaceRuntime();
    service = WorkspaceService(
      repository: repository,
      projectService: ProjectService(gitBackend),
      gitBackend: gitBackend,
      workspaceRoot: WorkspaceRoot(
        override: p.join(tempDir.path, 'workspaces'),
      ),
      managedRuntime: runtime,
      now: () => DateTime.utc(2026, 5, 20, 12),
    );
    final main = await service.ensureMainWorkspace(project);
    final child = main.copyWith(
      id: 'child',
      kind: .linked,
      branch: 'feat/back',
    );

    final result = await service.handOnWorkspace(
      workspace: child,
      activeWorkspaceId: child.id,
    );

    expect(result.removedWorkspaceId, 'child');
    expect(result.workspace.isMain, isTrue);
    expect(runtime.handOnWorkspaceId, 'child');
    expect(runtime.handOnActiveWorkspaceId, 'child');
  });
}

class _RecordingManagedWorkspaceRuntime implements ManagedWorkspaceRuntime {
  String? handOffBranch;
  String? handOffName;
  bool? handOffReuse;
  String? handOnWorkspaceId;
  String? handOnActiveWorkspaceId;

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
    handOffBranch = branch;
    handOffName = name;
    handOffReuse = reuseExistingBranch;
    final now = DateTime.utc(2026, 5, 20, 13);
    return WorkspaceCreationResult(
      workspace: Workspace(
        id: 'child',
        projectId: workspace.projectId,
        name: name ?? branch,
        branch: branch,
        path: p.join(tempDir.path, 'child'),
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
    handOnActiveWorkspaceId = activeWorkspaceId;
    final now = DateTime.utc(2026, 5, 20, 14);
    return WorkspaceHandOnResult(
      workspace: Workspace(
        id: 'main',
        projectId: workspace.projectId,
        name: 'Alera',
        branch: workspace.branch,
        path: project.repoPath,
        createdAt: now,
        updatedAt: now,
        kind: .main,
        status: .active,
      ),
      removedWorkspaceId: workspace.id,
    );
  }
}
