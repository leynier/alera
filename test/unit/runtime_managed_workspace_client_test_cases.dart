part of 'runtime_repositories_test.dart';

/// `RuntimeManagedWorkspaceClient`: the RPC that creates a linked workspace and
/// hands its worktree setup to a terminal.
///
/// Split out of `runtime_repositories_test.dart`, which covers the rest of the
/// runtime-host backed repositories.
void _registerRuntimeManagedWorkspaceClientTests() {
  test(
    'shared removal obtains buffer verification before retiring the task',
    () async {
      final client = _FakeRuntimeHostClient();
      client.responses['workspace.bufferGuard.acquire'] = {
        'guardId': 'proof',
        'ready': true,
      };
      final repository = RuntimeManagedWorkspaceClient(client);
      await repository.removeWorkspace(
        workspace: _workspace(
          id: 'task',
          projectId: 'project',
        ).copyWith(kind: .main),
        deleteBranch: false,
      );
      expect(client.requests, [
        'workspace.bufferGuard.acquire',
        'workspace.removeShared',
        'workspace.bufferGuard.release',
      ]);
      expect(
        client.payloads['workspace.removeShared']!.single['bufferGuardId'],
        'proof',
      );
    },
  );
  for (final owner in ['workspace', 'project']) {
    test(
      '$owner removal pauses approved dependencies and verifies completion',
      () async {
        final client = _FakeRuntimeHostClient();
        final repository = RuntimeManagedWorkspaceClient(client);
        client.responseSequences['$owner.removalDependencies'] = [
          [
            {
              'id': 'automation',
              'name': 'Daily Task',
              'activeRuns': 1,
              'requiresPause': true,
            },
          ],
          [
            {
              'id': 'automation',
              'name': 'Daily Task',
              'activeRuns': 0,
              'requiresPause': false,
            },
          ],
        ];
        final dependencies = await (owner == 'project'
            ? repository.projectRemovalDependencies(owner)
            : repository.removalDependencies(owner));
        await (owner == 'project'
            ? repository.pauseProjectRemovalDependencies(owner, dependencies)
            : repository.pauseRemovalDependencies(owner, dependencies));
        expect(
          client.payloads['automation.pause']!.single,
          containsPair('activeRuns', 'cancel-active'),
        );
        expect(
          client.payloads['automation.pause']!.single,
          containsPair('id', 'automation'),
        );
        expect(
          client.requests.where(
            (request) => request == '$owner.removalDependencies',
          ),
          hasLength(2),
        );
        expect(client.requests, isNot(contains('workspace.removeShared')));
      },
    );

    test(
      '$owner removal rejects newly discovered dependencies without pausing them',
      () async {
        final client = _FakeRuntimeHostClient();
        final repository = RuntimeManagedWorkspaceClient(client);
        client.responseSequences['$owner.removalDependencies'] = [
          <Object?>[],
          [
            {
              'id': 'new',
              'name': 'New Task',
              'activeRuns': 1,
              'requiresPause': true,
            },
          ],
        ];
        final dependencies = await (owner == 'project'
            ? repository.projectRemovalDependencies(owner)
            : repository.removalDependencies(owner));
        await expectLater(
          owner == 'project'
              ? repository.pauseProjectRemovalDependencies(owner, dependencies)
              : repository.pauseRemovalDependencies(owner, dependencies),
          throwsStateError,
        );
        expect(client.requests, isNot(contains('automation.pause')));
      },
    );
  }

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
      client.responses['workspace.bufferGuard.acquire'] = {
        'guardId': 'hand-off-guard',
        'ready': true,
      };
      client.responses['status.get'] = <String, Object?>{
        'runtimeCapabilities': <String>[aleraRuntimeHostSafeHandoffCapability],
      };
      client.responses['workspace.handOff'] = <String, Object?>{
        'workspace': _workspaceJson(id: 'workspace-main'),
        'setupReport': <String, Object?>{'steps': <Object?>[]},
        'deferredSetupCommand': '/bin/sh "/run/alera/worktree-setup-ws.sh"',
      };

      final result = await repository.handOffWorkspace(
        relocationId: '123e4567-e89b-12d3-a456-426614174000',
        workspace: _workspace(id: 'workspace-main', projectId: 'project-1'),
        branch: 'feat/hand-off',
        reuseExistingBranch: false,
        name: 'Hand Off',
      );

      expect(result.workspace.id, 'workspace-main');
      expect(
        result.deferredSetupCommand,
        '/bin/sh "/run/alera/worktree-setup-ws.sh"',
      );
      expect(client.payloads['workspace.handOff']!.single, <String, Object?>{
        'relocationId': '123e4567-e89b-12d3-a456-426614174000',
        'id': 'workspace-main',
        'branch': 'feat/hand-off',
        'reuseExistingBranch': false,
        'deferSetup': true,
        'moveChanges': true,
        'replacementBranch': null,
        'sharedImpactConfirmed': true,
        'bufferGuardId': 'hand-off-guard',
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

  for (final capabilities in <Object?>[
    null,
    <String>[],
    <String>['unrelatedCapabilityV1'],
    'safeWorkspaceHandoffV1',
  ]) {
    test(
      'RuntimeManagedWorkspaceClient refuses unsafe transfer capabilities: $capabilities',
      () async {
        final client = _FakeRuntimeHostClient();
        final repository = RuntimeManagedWorkspaceClient(client);
        client.responses['status.get'] = <String, Object?>{
          'runtimeCapabilities': capabilities,
        };
        final workspace = _workspace(id: 'workspace-1', projectId: 'project-1');

        await expectLater(
          repository.handOffWorkspace(
            workspace: workspace,
            branch: 'feature/safe-transfer',
            reuseExistingBranch: false,
          ),
          throwsA(isA<WorkspaceException>()),
        );
        await expectLater(
          repository.handOnWorkspace(workspace: workspace),
          throwsA(isA<WorkspaceException>()),
        );

        expect(client.payloads['workspace.handOff'], isNull);
        expect(client.payloads['workspace.handOn'], isNull);
      },
    );
  }

  test('RuntimeManagedWorkspaceClient hands on through the host RPC', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeManagedWorkspaceClient(client);
    client.responses['workspace.bufferGuard.acquire'] = {
      'guardId': 'hand-on-guard',
      'ready': true,
    };
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>[aleraRuntimeHostSafeHandoffCapability],
    };
    client.responses['workspace.handOn'] = <String, Object?>{
      'workspace': _workspaceJson(id: 'workspace-child'),
      'removedWorkspaceId': null,
    };

    final result = await repository.handOnWorkspace(
      relocationId: '123e4567-e89b-12d3-a456-426614174001',
      workspace: _workspace(id: 'workspace-child', projectId: 'project-1'),
      activeWorkspaceId: 'workspace-child',
    );

    expect(result.workspace.id, 'workspace-child');
    expect(result.removedWorkspaceId, isNull);
    expect(client.payloads['workspace.handOn']!.single, <String, Object?>{
      'relocationId': '123e4567-e89b-12d3-a456-426614174001',
      'id': 'workspace-child',
      'closeSessions': true,
      'activeWorkspaceId': 'workspace-child',
      'sharedImpactConfirmed': true,
      'bufferGuardId': 'hand-on-guard',
    });
  });
}
