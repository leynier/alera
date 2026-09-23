part of 'workspace_service_test.dart';

void _registerWorkspaceServiceSharedCheckoutTests() {
  test('reconcile leaves a project with no workspaces empty', () async {
    await service.reconcile(project);
    expect(await repository.listWorkspaces(project.id), isEmpty);
  });

  test(
    'shared workspaces have independent identity on the same folder',
    () async {
      final first = await service.createSharedWorkspace(project: project);
      final second = await service.createSharedWorkspace(project: project);
      expect(first.workspace.id, isNot(second.workspace.id));
      expect(first.workspace.name, isNot(second.workspace.name));
      expect(first.workspace.path, second.workspace.path);
      expect(first.setupReport.isEmpty, isTrue);
      expect(await repository.listWorkspaces(project.id), hasLength(2));
    },
  );

  test('workspace root throws when no home directory is available', () {
    expect(
      () => WorkspaceRoot(environment: const <String, String>{}).resolve(),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('createSharedWorkspace stores a task on the project checkout', () async {
    gitBackend.headBranch = 'main';

    final workspace = (await service.createSharedWorkspace(project: project))
        .workspace;

    expect(workspace.projectId, project.id);
    expect(workspace.name, 'Workspace 1');
    expect(workspace.branch, 'main');
    expect(workspace.path, project.repoPath);
    expect(workspace.kind, WorkspaceKind.main);
    expect(workspace.status, WorkspaceStatus.active);
    expect(repository.workspaces.single, workspace);
  });

  test('createSharedWorkspace stores a folder task without Git', () async {
    final folderProject = project.copyWith(kind: .folder);

    final workspace = (await service.createSharedWorkspace(
      project: folderProject,
    )).workspace;

    expect(workspace.projectId, folderProject.id);
    expect(workspace.name, 'Workspace 1');
    expect(workspace.branch, isNull);
    expect(workspace.path, folderProject.repoPath);
    expect(workspace.kind, WorkspaceKind.main);
    expect(workspace.status, WorkspaceStatus.active);
    expect(gitBackend.calls, isEmpty);
  });

  test('creating another task preserves existing task state', () async {
    final existing = Workspace(
      id: 'workspace-1',
      projectId: project.id,
      name: 'Production checkout',
      branch: 'old-main',
      path: '/old/path',
      createdAt: .utc(2026, 5, 19),
      updatedAt: .utc(2026, 5, 19),
      kind: .main,
      status: .active,
    );
    await repository.upsertWorkspace(existing);
    gitBackend.headBranch = 'main';

    final workspace = (await service.createSharedWorkspace(project: project))
        .workspace;

    expect(workspace.id, isNot(existing.id));
    expect(await repository.findWorkspaceById(existing.id), existing);
    expect(workspace.name, 'Workspace 1');
    expect(workspace.branch, 'main');
    expect(workspace.path, project.repoPath);
  });

  test(
    'shared creation falls back to HEAD when git cannot resolve a branch',
    () async {
      gitBackend.headBranchFails = true;

      final workspace = (await service.createSharedWorkspace(project: project))
          .workspace;

      expect(workspace.branch, 'HEAD');
    },
  );

  test('renames a workspace with a trimmed non-empty name', () async {
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: project.id,
      name: 'Old name',
      branch: 'main',
      path: project.repoPath,
      createdAt: .utc(2026, 5, 19),
      updatedAt: .utc(2026, 5, 19),
      kind: .main,
      status: .active,
    );
    await repository.upsertWorkspace(workspace);

    final renamed = await service.renameWorkspace(
      workspaceId: workspace.id,
      name: '  New name  ',
    );

    expect(renamed.name, 'New name');
    expect(renamed.updatedAt, DateTime.utc(2026, 5, 20, 12));
    expect(repository.workspaces.single.name, 'New name');
  });

  test('rejects a blank workspace name when renaming', () async {
    await expectLater(
      service.renameWorkspace(workspaceId: 'workspace-1', name: '   '),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('rejects renaming a workspace that does not exist', () async {
    await expectLater(
      service.renameWorkspace(workspaceId: 'missing-workspace', name: 'Main'),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('listSourceBranches skips folder projects', () async {
    final branches = await service.listSourceBranches(
      project.copyWith(kind: .folder),
    );

    expect(branches, isEmpty);
    expect(gitBackend.calls, isEmpty);
  });
}
