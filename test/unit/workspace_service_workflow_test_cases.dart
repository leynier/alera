part of 'workspace_service_test.dart';

void _registerWorkspaceServiceWorkflowTests() {
  for (final changedBranch in <String?>['HEAD', 'user/inspection', null]) {
    test(
      'reconcile preserves workflow identity with live branch $changedBranch',
      () async {
        gitBackend.headBranch = 'main';
        final mainWorkspace = await service.ensureMainWorkspace(project);
        Workspace linked(String id, {bool owned = false}) => Workspace(
          id: id,
          projectId: project.id,
          name: id,
          path: p.join(tempDir.path, id),
          branch: 'alera/workflows/$id',
          kind: .linked,
          status: .active,
          createdAt: .utc(2026, 5, 19),
          updatedAt: .utc(2026, 5, 19),
          workflowOwned: owned,
        );
        final task = linked('task', owned: true);
        final ordinary = linked('ordinary');
        final missing = linked('missing');
        await repository.upsertWorkspace(task);
        await repository.upsertWorkspace(ordinary);
        await repository.upsertWorkspace(missing);
        gitBackend.liveBranchByPath = <String, String>{
          project.repoPath: 'main',
          task.path: ?changedBranch,
          ordinary.path: 'feature/changed',
        };
        final tab = WorkspaceTabRecord(
          id: 'task-tab',
          workspaceId: task.id,
          kind: .terminal,
          title: 'Task',
          createdAt: task.createdAt,
          updatedAt: task.updatedAt,
        );
        await repository.upsertWorkspaceTab(tab);

        final result = await service.reconcile(project);

        expect(
          result.map((workspace) => workspace.id),
          containsAll(<String>[mainWorkspace.id, task.id, ordinary.id]),
        );
        expect(result.any((workspace) => workspace.id == missing.id), isFalse);
        expect(
          result.singleWhere((workspace) => workspace.id == task.id),
          task,
        );
        expect(
          result.singleWhere((workspace) => workspace.id == ordinary.id).branch,
          'feature/changed',
        );
        expect(
          await repository.listWorkspaceTabs(task.id),
          <WorkspaceTabRecord>[tab],
        );
        expect(
          (await service.ensureMainWorkspace(project)).id,
          mainWorkspace.id,
        );
      },
    );
  }

  test('folder reconciliation preserves retained workflow metadata', () async {
    final mainWorkspace = await service.ensureMainWorkspace(project);
    final task = mainWorkspace.copyWith(
      id: 'retained-task',
      kind: .linked,
      path: p.join(tempDir.path, 'retained-task'),
      workflowOwned: true,
    );
    await repository.upsertWorkspace(task);
    final result = await service.reconcile(project.copyWith(kind: .folder));
    expect(result.singleWhere((workspace) => workspace.id == task.id), task);
  });
}
