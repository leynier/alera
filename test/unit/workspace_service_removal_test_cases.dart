part of 'workspace_service_test.dart';

void _registerWorkspaceServiceRemovalTests() {
  test(
    'verified branch deletion uses force false after safe preflight',
    () async {
      final workspace = (await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/verified',
      )).workspace;
      _configureVerifiedBranchDeletion(workspace);
      await service.removeWorkspace(
        project: project,
        workspace: workspace,
        deleteBranch: true,
      );
      final deletion = gitBackend.calls.singleWhere(
        (call) => call.method == 'deleteBranch',
      );
      expect(deletion.args['force'], isFalse);
      expect(
        gitBackend.calls.indexWhere((call) => call.method == 'removeWorktree'),
        lessThan(
          gitBackend.calls.indexWhere((call) => call.method == 'deleteBranch'),
        ),
      );
      expect(await repository.findWorkspaceById(workspace.id), isNull);
    },
  );

  test('verified branch deletion accepts origin default when local default is stale', () async {
    final workspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/origin-merged',
    )).workspace;
    gitBackend.currentBranchesByPath[workspace.path] = workspace.branch!;
    gitBackend.ancestorResults[(workspace.branch!, 'main')] = false;
    gitBackend.ancestorResults[(workspace.branch!, 'origin/main')] = true;
    await service.removeWorkspace(
      project: project,
      workspace: workspace,
      deleteBranch: true,
    );
    expect(
      gitBackend.calls.any((call) => call.method == 'deleteBranch'),
      isTrue,
    );
    expect(gitBackend.sourceBranches, isNot(contains(workspace.branch)));
    expect(await repository.findWorkspaceById(workspace.id), isNull);
  });

  for (final reason in ['unknown', 'mismatch']) {
    test(
      'branch deletion keeps the branch on $reason identity and still removes the worktree',
      () async {
        final workspace = (await service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/refused',
        )).workspace;
        _configureVerifiedBranchDeletion(workspace);
        switch (reason) {
          case 'unknown':
            gitBackend.headBranchFails = true;
          case 'mismatch':
            gitBackend.currentBranchesByPath[workspace.path] = 'other';
        }
        await service.removeWorkspace(
          project: project,
          workspace: workspace,
          deleteBranch: true,
        );
        expect(
          gitBackend.calls.any((call) => call.method == 'removeWorktree'),
          isTrue,
        );
        expect(
          gitBackend.calls.any((call) => call.method == 'deleteBranch'),
          isFalse,
        );
        expect(await repository.findWorkspaceById(workspace.id), isNull);
      },
    );
  }

  test('unmerged safe-delete failure keeps the branch and still removes the worktree', () async {
    final workspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/unmerged',
    )).workspace;
    _configureVerifiedBranchDeletion(workspace);
    gitBackend.failingBranchDeletes.add(workspace.branch!);
    await service.removeWorkspace(
      project: project,
      workspace: workspace,
      deleteBranch: true,
    );
    expect(
      gitBackend.calls.any((call) => call.method == 'removeWorktree'),
      isTrue,
    );
    expect(
      gitBackend.calls.any((call) => call.method == 'deleteBranch'),
      isTrue,
    );
    expect(await repository.findWorkspaceById(workspace.id), isNull);
  });

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
        deleteBranch: false,
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
        deleteBranch: false,
      ),
      throwsA(
        isA<WorkspaceException>().having(
          (error) => error.toString(),
          'worktree error',
          contains('git worktree remove failed'),
        ),
      ),
    );
    expect(
      gitBackend.calls.any((call) => call.method == 'removeWorktree'),
      isTrue,
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
      deleteBranch: false,
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
        deleteBranch: false,
      ),
      throwsA(
        isA<WorkspaceException>().having(
          (error) => error.toString(),
          'worktree error',
          contains('git worktree remove failed'),
        ),
      ),
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
    _configureVerifiedBranchDeletion(linkedWorkspace);

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

  test('removeWorkspace keeps the branch when safe deletion fails after worktree removal', () async {
    gitBackend.sourceBranches = <String>['main'];
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/branch-failure',
    )).workspace;
    gitBackend.failingBranchDeletes.add('feature/branch-failure');
    _configureVerifiedBranchDeletion(linkedWorkspace);

    await service.removeWorkspace(
      project: project,
      workspace: linkedWorkspace,
      deleteBranch: true,
    );

    expect(
      gitBackend.calls.any((call) => call.method == 'deleteBranch'),
      isTrue,
    );
    expect(await repository.findWorkspaceById(linkedWorkspace.id), isNull);
  });

  test(
    'removeWorkspace keeps an unknown branch and still removes the worktree',
    () async {
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

      await service.removeWorkspace(
        project: project,
        workspace: branchlessWorkspace,
        deleteBranch: true,
      );

      expect(
        gitBackend.calls.any((call) => call.method == 'deleteBranch'),
        isFalse,
      );
      expect(
        gitBackend.calls.any((call) => call.method == 'removeWorktree'),
        isTrue,
      );
      expect(
        await repository.findWorkspaceById(branchlessWorkspace.id),
        isNull,
      );
    },
  );

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

void _configureVerifiedBranchDeletion(Workspace workspace) {
  gitBackend.currentBranchesByPath[workspace.path] = workspace.branch!;
  gitBackend.ancestorResults[(
        workspace.branch!,
        gitBackend.defaultBranchName,
      )] =
      true;
}
