part of 'runtime_repositories_test.dart';

/// `RuntimeManagedWorkspaceClient`: the RPC that creates a linked workspace and
/// hands its worktree setup to a terminal.
///
/// Split out of `runtime_repositories_test.dart`, which covers the rest of the
/// runtime-host backed repositories.
void _registerRuntimeManagedWorkspaceClientTests() {
  test(
    'RuntimeManagedWorkspaceClient uses long-running RPC timeouts',
    () async {
      final client = _FakeRuntimeHostClient();
      final repository = RuntimeManagedWorkspaceClient(client);
      client.responses['workspace.createManaged'] = <String, Object?>{
        'workspace': _workspaceJson(id: 'workspace-1'),
        'setupReport': <String, Object?>{'steps': <Object?>[]},
      };

      await repository.createLinkedWorkspace(
        project: _project(id: 'project-1', name: 'Alera'),
        sourceBranch: 'main',
        newBranchName: 'feature/managed',
        reuseExistingBranch: false,
      );
      await repository.removeWorkspace(
        workspace: _workspace(id: 'workspace-1', projectId: 'project-1'),
        deleteBranch: true,
      );

      expect(client.timeouts['workspace.createManaged'], <Duration?>[
        const Duration(minutes: 30),
      ]);
      expect(client.timeouts['workspace.removeManaged'], <Duration?>[
        const Duration(minutes: 10),
      ]);
    },
  );

  test(
    'RuntimeManagedWorkspaceClient defers the worktree setup to a terminal',
    () async {
      final client = _FakeRuntimeHostClient();
      final repository = RuntimeManagedWorkspaceClient(client);
      client.responses['workspace.createManaged'] = <String, Object?>{
        'workspace': _workspaceJson(id: 'workspace-1'),
        'setupReport': <String, Object?>{'steps': <Object?>[]},
        'deferredSetupCommand': '/bin/sh "/run/alera/worktree-setup-ws.sh"',
      };

      final result = await repository.createLinkedWorkspace(
        project: _project(id: 'project-1', name: 'Alera'),
        sourceBranch: 'main',
        newBranchName: 'feature/managed',
        reuseExistingBranch: false,
      );

      expect(
        client.payloads['workspace.createManaged']!.single['deferSetup'],
        isTrue,
      );
      expect(
        result.deferredSetupCommand,
        '/bin/sh "/run/alera/worktree-setup-ws.sh"',
      );
    },
  );

  test(
    'RuntimeManagedWorkspaceClient accepts a host that ran the setup inline',
    () async {
      final client = _FakeRuntimeHostClient();
      final repository = RuntimeManagedWorkspaceClient(client);
      // A host without deferral support ignores the flag and omits the command.
      client.responses['workspace.createManaged'] = <String, Object?>{
        'workspace': _workspaceJson(id: 'workspace-1'),
        'setupReport': <String, Object?>{
          'steps': <Object?>[
            <String, Object?>{
              'kind': 'command',
              'label': 'pnpm install',
              'succeeded': true,
            },
          ],
        },
      };

      final result = await repository.createLinkedWorkspace(
        project: _project(id: 'project-1', name: 'Alera'),
        sourceBranch: 'main',
        newBranchName: 'feature/managed',
        reuseExistingBranch: false,
      );

      expect(result.deferredSetupCommand, isNull);
      expect(result.setupReport.steps, hasLength(1));
    },
  );
}
