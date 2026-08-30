part of 'workspace_service_test.dart';

void _registerWorkspaceServiceRemovalTests() {
  test(
    'removeWorkspace deletes the workspace and cascades its workspace tabs',
    () async {
      gitBackend.sourceBranches = <String>['main'];
      final linkedWorkspace = (await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/with-tabs',
      )).workspace;
      await repository.upsertWorkspaceTab(
        WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: linkedWorkspace.id,
          title: 'Terminal 1',
          createdAt: .utc(2026, 5, 20),
          updatedAt: .utc(2026, 5, 20),
        ),
      );

      await service.removeWorkspace(
        project: project,
        workspace: linkedWorkspace,
        deleteBranch: true,
      );

      expect(
        repository.workspaces.any(
          (workspace) => workspace.id == linkedWorkspace.id,
        ),
        isFalse,
      );
      expect(await repository.listWorkspaceTabs(linkedWorkspace.id), isEmpty);
    },
  );

  test('removeWorkspace rejects removing the main workspace', () async {
    final mainWorkspace = await service.ensureMainWorkspace(project);

    await expectLater(
      service.removeWorkspace(
        project: project,
        workspace: mainWorkspace,
        deleteBranch: true,
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('removeWorkspace keeps the branch when deleteBranch is false', () async {
    gitBackend.sourceBranches = <String>['main'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/keep-branch',
    )).workspace;

    await service.removeWorkspace(
      project: project,
      workspace: linkedWorkspace,
      deleteBranch: false,
    );

    expect(
      gitBackend.calls.any((call) => call.method == 'deleteBranch'),
      isFalse,
    );
    expect(
      repository.workspaces.any(
        (workspace) => workspace.id == linkedWorkspace.id,
      ),
      isFalse,
    );
  });

  test('removeWorkspace keeps reused existing branches by default', () async {
    gitBackend.sourceBranches = <String>['main', 'feature/reused'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'feature/reused',
      newBranchName: 'feature/reused',
      reuseExistingBranch: true,
    )).workspace;

    await service.removeWorkspace(
      project: project,
      workspace: linkedWorkspace,
      deleteBranch: true,
    );

    expect(
      gitBackend.calls.any((call) => call.method == 'deleteBranch'),
      isFalse,
    );
    expect(
      repository.workspaces.any(
        (workspace) => workspace.id == linkedWorkspace.id,
      ),
      isFalse,
    );
  });

  test(
    'removeWorkspace preserves reused branches when delegated to runtime',
    () async {
      gitBackend.sourceBranches = <String>['main', 'feature/runtime-reused'];
      final linkedWorkspace = (await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'feature/runtime-reused',
        newBranchName: 'feature/runtime-reused',
        reuseExistingBranch: true,
      )).workspace;
      final managedRuntime = _FakeManagedWorkspaceRuntime();
      final managedService = WorkspaceService(
        repository: repository,
        projectService: ProjectService(gitBackend),
        gitBackend: gitBackend,
        managedRuntime: managedRuntime,
      );

      await managedService.removeWorkspace(
        project: project,
        workspace: linkedWorkspace,
        deleteBranch: true,
      );

      expect(managedRuntime.removedWorkspace, linkedWorkspace);
      expect(managedRuntime.deleteBranch, isFalse);
    },
  );

  test('removeWorkspace surfaces git worktree removal failures', () async {
    gitBackend.sourceBranches = <String>['main'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/remove-failure',
    )).workspace;
    gitBackend.failingWorktreeRemovePaths.add(linkedWorkspace.path);

    await expectLater(
      service.removeWorkspace(
        project: project,
        workspace: linkedWorkspace,
        deleteBranch: true,
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('removeWorkspace removes stale metadata when worktree and branch are missing', () async {
    gitBackend.sourceBranches = <String>['main'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/stale',
    )).workspace;
    gitBackend.removeWorktreeError = WorktreeNotFoundException(
      linkedWorkspace.path,
    );
    gitBackend.deleteBranchError = const BranchNotFoundException(
      'feature/stale',
    );

    await service.removeWorkspace(
      project: project,
      workspace: linkedWorkspace,
      deleteBranch: true,
    );

    expect(
      repository.workspaces.any(
        (workspace) => workspace.id == linkedWorkspace.id,
      ),
      isFalse,
    );
  });

  test('removeWorkspace preserves an unregistered filesystem entry', () async {
    gitBackend.sourceBranches = <String>['main'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/occupied',
    )).workspace;
    final sentinel = File(p.join(linkedWorkspace.path, 'keep.txt'));
    sentinel.createSync(recursive: true);
    sentinel.writeAsStringSync('keep');
    gitBackend.removeWorktreeError = WorktreeNotFoundException(
      linkedWorkspace.path,
    );

    await expectLater(
      service.removeWorkspace(
        project: project,
        workspace: linkedWorkspace,
        deleteBranch: true,
      ),
      throwsA(isA<WorkspaceException>()),
    );

    expect(sentinel.existsSync(), isTrue);
    expect(
      repository.workspaces.any(
        (workspace) => workspace.id == linkedWorkspace.id,
      ),
      isTrue,
    );
    expect(
      gitBackend.calls.any((call) => call.method == 'deleteBranch'),
      isFalse,
    );
  });

  test('removeWorkspace accepts an already deleted branch', () async {
    gitBackend.sourceBranches = <String>['main'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/missing-branch',
    )).workspace;
    gitBackend.deleteBranchError = const BranchNotFoundException(
      'feature/missing-branch',
    );

    await service.removeWorkspace(
      project: project,
      workspace: linkedWorkspace,
      deleteBranch: true,
    );

    expect(
      repository.workspaces.any(
        (workspace) => workspace.id == linkedWorkspace.id,
      ),
      isFalse,
    );
  });

  test('removeWorkspace surfaces git branch deletion failures', () async {
    gitBackend.sourceBranches = <String>['main'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/branch-failure',
    )).workspace;
    gitBackend.failingBranchDeletes.add('feature/branch-failure');

    await expectLater(
      service.removeWorkspace(
        project: project,
        workspace: linkedWorkspace,
        deleteBranch: true,
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('removeWorkspace requires a branch when deleting it', () async {
    final branchlessWorkspace = Workspace(
      id: 'workspace-branchless',
      projectId: project.id,
      name: 'Detached',
      branch: '',
      path: p.join(tempDir.path, 'detached'),
      createdAt: .utc(2026, 5, 20),
      updatedAt: .utc(2026, 5, 20),
      kind: .linked,
      status: .active,
    );

    await expectLater(
      service.removeWorkspace(
        project: project,
        workspace: branchlessWorkspace,
        deleteBranch: true,
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('WorkspaceException includes stderr only when present', () {
    expect(WorkspaceException('Could not open').toString(), 'Could not open');
    expect(
      WorkspaceException('Could not open', stderr: 'fatal error\n').toString(),
      'Could not open: fatal error',
    );
  });

  test('WorkspaceRoot resolves the default HOME-based path', () {
    final resolved = WorkspaceRoot().resolve();

    expect(resolved, endsWith(p.join('.alera', 'workspaces')));
    expect(
      resolved,
      contains(
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!,
      ),
    );
  });

  test('WorkspaceService defaults timestamps to current utc time', () async {
    final defaultService = WorkspaceService(
      repository: repository,
      projectService: ProjectService(gitBackend),
      gitBackend: gitBackend,
    );
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));

    final workspace = await defaultService.ensureMainWorkspace(project);

    final after = DateTime.now().toUtc().add(const Duration(seconds: 1));
    expect(workspace.updatedAt.isUtc, isTrue);
    expect(workspace.updatedAt.isAfter(before), isTrue);
    expect(workspace.updatedAt.isBefore(after), isTrue);
  });
}
