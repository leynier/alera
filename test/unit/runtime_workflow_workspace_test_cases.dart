part of 'runtime_repositories_test.dart';

void _registerRuntimeWorkflowWorkspaceTests() {
  test('workspace snapshots parse ownership in one request and default legacy hosts safely', () async {
    final client = _FakeRuntimeHostClient();
    final repository = RuntimeWorkbenchRepository(client);
    client.responses['workspace.list'] = <Object?>[
      <String, Object?>{..._workspaceJson(id: 'owned'), 'workflowOwned': true},
      <String, Object?>{
        ..._workspaceJson(id: 'ordinary'),
        'workflowOwned': false,
      },
      _workspaceJson(id: 'legacy'),
    ];
    final workspaces = await repository.listWorkspaces('project-1');
    expect(workspaces.map((workspace) => workspace.workflowOwned), <bool>[
      true,
      false,
      false,
    ]);
    expect(client.requests, <String>['workspace.list']);
    final roundTrip = Workspace.fromJson(workspaces.first.toMap());
    expect(roundTrip.workflowOwned, isTrue);
  });
}
