part of 'workspace_service_test.dart';

void _registerWorkspaceServiceCoreTests() {
  test('createLinkedWorkspace creates a new worktree from the requested source branch', () async {
    gitBackend.sourceBranches = <String>['main', 'origin/main'];

    final result = await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'origin/main',
      newBranchName: 'feature/terminal-tabs',
    );
    final workspace = result.workspace;

    expect(workspace.kind, WorkspaceKind.linked);
    expect(workspace.sourceBranch, 'origin/main');
    expect(workspace.branch, 'feature/terminal-tabs');
    expect(workspace.reusesExistingBranch, isFalse);
    expect(workspace.name, 'feature/terminal-tabs');
    expect(workspace.path, contains('project-1'));
    expect(
      gitBackend.calls.map((call) => call.method),
      containsAllInOrder(<String>[
        'isValidBranchName',
        'listBranches',
        'branchExists',
        'refreshSourceBranch',
        'createWorktree',
      ]),
    );
    final refreshCall = gitBackend.calls.lastWhere(
      (call) => call.method == 'refreshSourceBranch',
    );
    expect(refreshCall.args, <String, Object?>{
      'repoPath': project.repoPath,
      'sourceBranch': 'origin/main',
    });
    final createCall = gitBackend.calls.lastWhere(
      (call) => call.method == 'createWorktree',
    );
    expect(createCall.args, <String, Object?>{
      'repoPath': project.repoPath,
      'targetBranch': 'feature/terminal-tabs',
      'path': workspace.path,
      'sourceBranch': 'origin/main',
      'reuseExistingBranch': false,
    });
  });

  test(
    'createLinkedWorkspace surfaces source branch refresh failures',
    () async {
      gitBackend.sourceBranches = <String>['main'];
      gitBackend.refreshSourceBranchError = const GitCliException(
        'pull failed',
      );

      await expectLater(
        service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/refresh-failure',
        ),
        throwsA(
          isA<WorkspaceException>()
              .having(
                (error) => error.message,
                'message',
                'git source branch refresh failed',
              )
              .having((error) => error.stderr, 'stderr', 'pull failed'),
        ),
      );

      expect(
        gitBackend.calls.map((call) => call.method),
        isNot(contains('createWorktree')),
      );
      expect(repository.workspaces, isEmpty);
      expect(
        Directory(p.join(tempDir.path, 'workspaces', 'repo-project-1'))
            .existsSync(),
        isFalse,
      );
    },
  );

  test('createLinkedWorkspace can reuse an existing local branch', () async {
    gitBackend.sourceBranches = <String>['main', 'feature/existing'];

    final workspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'feature/existing',
      newBranchName: 'feature/existing',
      reuseExistingBranch: true,
      name: 'Existing workspace',
    )).workspace;

    expect(workspace.kind, WorkspaceKind.linked);
    expect(workspace.sourceBranch, isNull);
    expect(workspace.branch, 'feature/existing');
    expect(workspace.reusesExistingBranch, isTrue);
    expect(workspace.name, 'Existing workspace');
    final createCall = gitBackend.calls.lastWhere(
      (call) => call.method == 'createWorktree',
    );
    expect(createCall.args, <String, Object?>{
      'repoPath': project.repoPath,
      'targetBranch': 'feature/existing',
      'path': workspace.path,
      'sourceBranch': 'feature/existing',
      'reuseExistingBranch': true,
    });
  });

  test('createLinkedWorkspace rejects a blank source branch', () async {
    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: '   ',
        newBranchName: 'feature/blank-source',
      ),
      throwsA(isA<WorkspaceException>()),
    );

    expect(gitBackend.calls, isEmpty);
  });

  test('createLinkedWorkspace rejects a blank new branch name', () async {
    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: '   ',
      ),
      throwsA(isA<WorkspaceException>()),
    );

    expect(gitBackend.calls, isEmpty);
  });

  test('createLinkedWorkspace rejects invalid git branch names', () async {
    gitBackend.invalidBranchNames.add('bad branch');

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'bad branch',
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('createLinkedWorkspace rejects missing sources and existing target branches', () async {
    gitBackend.sourceBranches = <String>['develop'];

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/missing-source',
      ),
      throwsA(isA<WorkspaceException>()),
    );

    gitBackend.sourceBranches = <String>['main', 'feature/existing'];

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/existing',
      ),
      throwsA(isA<WorkspaceException>()),
    );

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'feature/missing-existing',
        newBranchName: 'feature/missing-existing',
        reuseExistingBranch: true,
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('createLinkedWorkspace surfaces git worktree add failures', () async {
    gitBackend.sourceBranches = <String>['main'];
    gitBackend.failingWorktreeAddBranches.add('feature/add-failure');

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/add-failure',
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test(
    'createLinkedWorkspace keeps the workspace when setup config fails',
    () async {
      gitBackend.sourceBranches = <String>['main'];
      service = WorkspaceService(
        repository: repository,
        projectService: ProjectService(gitBackend),
        gitBackend: gitBackend,
        workspaceRoot: WorkspaceRoot(
          override: p.join(tempDir.path, 'workspaces'),
        ),
        projectConfigReader: const _FailingProjectConfigReader(),
        now: () => DateTime.utc(2026, 5, 20, 12),
      );

      final result = await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/setup-warning',
      );

      expect(result.hasSetupWarnings, isTrue);
      expect(
        result.setupReport.steps.single.kind,
        WorktreeSetupStepKind.config,
      );
      expect(repository.workspaces.single.id, result.workspace.id);
    },
  );

  test('createLinkedWorkspace rejects duplicate branches, paths, and invalid slugs', () async {
    gitBackend.sourceBranches = <String>['main'];
    await repository.upsertWorkspace(
      Workspace(
        id: 'workspace-existing-branch',
        projectId: project.id,
        name: 'Existing branch',
        branch: 'feature/duplicate',
        path: p.join(tempDir.path, 'duplicate-branch'),
        createdAt: .utc(2026, 5, 19),
        updatedAt: .utc(2026, 5, 19),
        kind: .linked,
        status: .active,
      ),
    );

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/duplicate',
      ),
      throwsA(isA<WorkspaceException>()),
    );

    await repository.upsertWorkspace(
      Workspace(
        id: 'workspace-existing-path',
        projectId: project.id,
        name: 'Existing path',
        branch: 'feature/other',
        path: p.join(
          tempDir.path,
          'workspaces',
          'repo-project-1',
          'feature-path-dup',
        ),
        createdAt: .utc(2026, 5, 19),
        updatedAt: .utc(2026, 5, 19),
        kind: .linked,
        status: .active,
      ),
    );

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/path-dup',
      ),
      throwsA(isA<WorkspaceException>()),
    );

    await expectLater(
      service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/slug',
        name: '!!!',
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test(
    'reconcile keeps the main workspace and removes missing linked ones',
    () async {
      gitBackend.headBranch = 'main';
      gitBackend.sourceBranches = <String>['main'];
      final mainWorkspace = (await service.createSharedWorkspace(
        project: project,
      )).workspace;
      final linkedWorkspace = (await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/remove-me',
      )).workspace;
      gitBackend.liveBranchByPath = <String, String>{project.repoPath: 'main'};

      final workspaces = await service.reconcile(project);

      expect(workspaces.map((workspace) => workspace.id), <String>[
        mainWorkspace.id,
      ]);
      expect(
        workspaces
            .singleWhere((workspace) => workspace.id == mainWorkspace.id)
            .status,
        WorkspaceStatus.active,
      );
      expect(
        repository.workspaces.any(
          (workspace) => workspace.id == linkedWorkspace.id,
        ),
        isFalse,
      );
    },
  );

  test(
    'reconcile keeps linked workspaces when git worktree list fails',
    () async {
      gitBackend.headBranch = 'main';
      gitBackend.sourceBranches = <String>['main'];
      final mainWorkspace = (await service.createSharedWorkspace(
        project: project,
      )).workspace;
      final linkedWorkspace = (await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/keep-me',
      )).workspace;
      gitBackend.worktreeListFails = true;

      final workspaces = await service.reconcile(project);

      expect(
        workspaces.map((workspace) => workspace.id),
        containsAll(<String>[mainWorkspace.id, linkedWorkspace.id]),
      );
    },
  );

  test(
    'reconcile updates linked workspace metadata from live worktrees',
    () async {
      gitBackend.headBranch = 'main';
      gitBackend.sourceBranches = <String>['main'];
      (await service.createSharedWorkspace(project: project)).workspace;
      final linkedWorkspace = (await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/live-rename',
      )).workspace;
      gitBackend.liveBranchByPath = <String, String>{
        project.repoPath: 'main',
        linkedWorkspace.path: 'feature/live-updated',
      };

      final workspaces = await service.reconcile(project);

      expect(
        workspaces
            .singleWhere((workspace) => workspace.id == linkedWorkspace.id)
            .branch,
        'feature/live-updated',
      );
    },
  );

  test('reconcile skips pruning when the live list does not include the main workspace', () async {
    gitBackend.headBranch = 'main';
    gitBackend.sourceBranches = <String>['main'];
    (await service.createSharedWorkspace(project: project)).workspace;
    final linkedWorkspace = (await service.createLinkedWorkspace(
      project: project,
      sourceBranch: 'main',
      newBranchName: 'feature/cannot-prune',
    )).workspace;
    gitBackend.liveBranchByPath = <String, String>{
      linkedWorkspace.path: 'feature/cannot-prune',
    };

    final workspaces = await service.reconcile(project);

    expect(
      workspaces.map((workspace) => workspace.id),
      contains(linkedWorkspace.id),
    );
  });

  test(
    'reconcile preserves existing records when a project is a folder',
    () async {
      final folderProject = project.copyWith(kind: .folder);
      final linkedWorkspace = Workspace(
        id: 'linked-folder-workspace',
        projectId: folderProject.id,
        name: 'Linked',
        branch: 'feature/remove-me',
        path: p.join(tempDir.path, 'linked-folder-workspace'),
        createdAt: .utc(2026, 5, 20),
        updatedAt: .utc(2026, 5, 20),
        kind: .linked,
        status: .active,
      );
      await repository.upsertWorkspace(linkedWorkspace);

      final workspaces = await service.reconcile(folderProject);

      expect(workspaces, hasLength(1));
      expect(workspaces.single.id, linkedWorkspace.id);
      expect(workspaces.single.branch, linkedWorkspace.branch);
      expect(
        repository.workspaces.any(
          (workspace) => workspace.id == linkedWorkspace.id,
        ),
        isTrue,
      );
      expect(gitBackend.calls, isEmpty);
    },
  );

  test(
    'createLinkedWorkspace rejects folder projects before Git calls',
    () async {
      final folderProject = project.copyWith(kind: .folder);

      await expectLater(
        service.createLinkedWorkspace(
          project: folderProject,
          sourceBranch: 'main',
          newBranchName: 'feature/not-allowed',
        ),
        throwsA(isA<WorkspaceException>()),
      );

      expect(gitBackend.calls, isEmpty);
    },
  );
}
