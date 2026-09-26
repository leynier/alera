part of 'workspace_service_test.dart';

void _registerWorkspaceServiceRemoteHostTests() {
  test(
    'createLinkedWorkspace refuses a remote host without a runtime host',
    () async {
      await expectLater(
        service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/remote',
          hostId: 'ssh-box',
        ),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.toString(),
            'message',
            contains('runtime host'),
          ),
        ),
      );
      expect(gitBackend.calls, isEmpty);
    },
  );

  test(
    'a remote-only project is never reconciled or listed from a local path',
    () async {
      final remoteOnly = project.copyWith(
        repoPath: '/srv/only-there',
        primaryHostId: 'ssh-box',
      );
      final remoteWorkspace = Workspace(
        id: 'remote-task',
        projectId: remoteOnly.id,
        name: 'Remote Task',
        branch: 'feature/remote',
        path: '/srv/alera-workspaces/remote-task',
        hostId: 'ssh-box',
        createdAt: .utc(2026, 9, 21),
        updatedAt: .utc(2026, 9, 21),
        kind: .linked,
        status: .active,
      );
      await repository.upsertWorkspace(remoteWorkspace);

      final workspaces = await service.reconcile(remoteOnly);
      final branches = await service.listSourceBranches(remoteOnly);

      expect(workspaces.map((workspace) => workspace.id), <String>[
        remoteWorkspace.id,
      ]);
      expect(branches, isEmpty);
      expect(gitBackend.calls, isEmpty);
    },
  );
}
