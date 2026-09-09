part of 'runtime_repositories_test.dart';

/// `RuntimeManagedWorkspaceClient`: the RPC that creates a linked workspace and
/// hands its worktree setup to a terminal.
///
/// Split out of `runtime_repositories_test.dart`, which covers the rest of the
/// runtime-host backed repositories.
void _registerRuntimeManagedWorkspaceClientTests() {
  test('RuntimeManagedWorkspaceClient parses storage impact', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeManagedWorkspaceClient(client);
    client.responses['workspace.storageImpact'] = <String, Object?>{
      'workspaceId': 'workspace-1',
      'path': '/managed/workspace-1',
      'sizeBytes': 4096,
      'entryCount': 12,
      'measuredAt': '2026-08-22T10:00:00Z',
      'lastActivityAt': '2026-08-21T09:00:00Z',
      'safeToClean': false,
      'blockers': <String>['Workspace is active in the workbench'],
    };

    final impact = await repository.storageImpact(
      workspaceId: 'workspace-1',
      activeWorkspaceId: 'workspace-1',
    );

    expect(impact.sizeBytes, 4096);
    expect(impact.entryCount, 12);
    expect(impact.safeToClean, isFalse);
    expect(impact.blockers, <String>['Workspace is active in the workbench']);
    expect(
      client.payloads['workspace.storageImpact']!.single,
      <String, Object?>{
        'id': 'workspace-1',
        'activeWorkspaceId': 'workspace-1',
        'closeSessions': true,
      },
    );
  });

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
        activeWorkspaceId: 'workspace-2',
      );

      expect(client.timeouts['workspace.createManaged'], <Duration?>[
        const Duration(minutes: 30),
      ]);
      expect(client.timeouts['workspace.removeManaged'], <Duration?>[
        const Duration(minutes: 10),
      ]);
      expect(
        client.payloads['workspace.removeManaged']!.single,
        <String, Object?>{
          'id': 'workspace-1',
          'activeWorkspaceId': 'workspace-2',
          'deleteBranch': true,
          'closeSessions': true,
        },
      );
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

  test(
    'RuntimeManagedWorkspaceClient hands off through the host RPC',
    () async {
      final client = _FakeRuntimeHostClient();
      final repository = RuntimeManagedWorkspaceClient(client);
      client.responses['workspace.handOff'] = <String, Object?>{
        'workspace': _workspaceJson(id: 'workspace-child'),
        'setupReport': <String, Object?>{'steps': <Object?>[]},
        'deferredSetupCommand': '/bin/sh "/run/alera/worktree-setup-ws.sh"',
      };

      final result = await repository.handOffWorkspace(
        workspace: _workspace(id: 'workspace-main', projectId: 'project-1'),
        branch: 'feat/hand-off',
        reuseExistingBranch: false,
        name: 'Hand Off',
      );

      expect(result.workspace.id, 'workspace-child');
      expect(
        result.deferredSetupCommand,
        '/bin/sh "/run/alera/worktree-setup-ws.sh"',
      );
      expect(client.payloads['workspace.handOff']!.single, <String, Object?>{
        'id': 'workspace-main',
        'branch': 'feat/hand-off',
        'reuseExistingBranch': false,
        'deferSetup': true,
        'name': 'Hand Off',
      });
    },
  );

  test('RuntimeManagedWorkspaceClient sends hostId when the sidecar supports remote workspaces', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeManagedWorkspaceClient(client);
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>[
        aleraRuntimeHostRemoteSshWorkspacesCapability,
      ],
    };
    client.responses['workspace.createManaged'] = <String, Object?>{
      'workspace': _workspaceJson(id: 'workspace-remote'),
      'setupReport': <String, Object?>{'steps': <Object?>[]},
    };

    await repository.createLinkedWorkspace(
      project: _project(id: 'project-1', name: 'Alera'),
      sourceBranch: 'main',
      newBranchName: 'feature/remote',
      reuseExistingBranch: false,
      hostId: 'ssh-box',
    );

    expect(
      client.payloads['workspace.createManaged']!.single['hostId'],
      'ssh-box',
    );
  });

  test('RuntimeManagedWorkspaceClient refuses hostId without remoteSshWorkspacesV1', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeManagedWorkspaceClient(client);
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>[],
    };

    await expectLater(
      repository.createLinkedWorkspace(
        project: _project(id: 'project-1', name: 'Alera'),
        sourceBranch: 'main',
        newBranchName: 'feature/remote',
        reuseExistingBranch: false,
        hostId: 'ssh-box',
      ),
      throwsA(isA<WorkspaceException>()),
    );
    expect(client.payloads['workspace.createManaged'], isNull);
  });

  test('RuntimeManagedWorkspaceClient hands on through the host RPC', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeManagedWorkspaceClient(client);
    client.responses['workspace.handOn'] = <String, Object?>{
      'workspace': _workspaceJson(id: 'workspace-main'),
      'removedWorkspaceId': 'workspace-child',
    };

    final result = await repository.handOnWorkspace(
      workspace: _workspace(id: 'workspace-child', projectId: 'project-1'),
      activeWorkspaceId: 'workspace-child',
    );

    expect(result.workspace.id, 'workspace-main');
    expect(result.removedWorkspaceId, 'workspace-child');
    expect(client.payloads['workspace.handOn']!.single, <String, Object?>{
      'id': 'workspace-child',
      'closeSessions': true,
      'activeWorkspaceId': 'workspace-child',
    });
  });
}
