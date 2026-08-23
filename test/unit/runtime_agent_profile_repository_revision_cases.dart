part of 'runtime_agent_profile_repository_test.dart';

void _registerAgentProfileRevisionRepositoryTests() {
  test('upsert requires a revision when updating a profile', () async {
    final repository = RuntimeAgentProfileRepository(_FakeRuntimeHostClient());

    await expectLater(
      repository.upsert(
        id: 'prof_1',
        name: 'Renamed',
        agentType: 'codex',
        launchMode: AgentProfileLaunchMode.command,
        command: 'codex',
      ),
      throwsArgumentError,
    );
  });

  test('upsert sends the id when updating a profile', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>[
        aleraRuntimeHostAgentProfileRevisionsCapability,
      ],
    };
    client.responses['agentProfile.upsert'] = _profilePayload(
      'prof_1',
      'Renamed',
    );
    final repository = RuntimeAgentProfileRepository(client);

    await repository.upsert(
      id: 'prof_1',
      expectedRevision: 4,
      name: 'Renamed',
      agentType: 'codex',
      launchMode: AgentProfileLaunchMode.command,
      command: 'codex',
      customPrompt: 'Use The Team Conventions',
      quotaGroup: 'codex-personal',
    );

    final payload = client.payloads['agentProfile.upsert']!.single;
    expect(payload['id'], 'prof_1');
    expect(payload['expectedRevision'], 4);
    expect(payload['quotaGroup'], 'codex-personal');
    expect(payload['customPrompt'], 'Use The Team Conventions');
  });

  test('upsert refuses to update through an older live host', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': const <String>[],
    };
    final repository = RuntimeAgentProfileRepository(client);

    await expectLater(
      repository.upsert(
        id: 'prof_1',
        expectedRevision: 4,
        name: 'Renamed',
        agentType: 'codex',
        launchMode: AgentProfileLaunchMode.command,
        command: 'codex',
      ),
      throwsA(isA<StateError>()),
    );
    expect(client.payloads['agentProfile.upsert'], isNull);
  });

  test('remove refuses an older live host', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': const <String>[],
    };
    final repository = RuntimeAgentProfileRepository(client);

    await expectLater(
      repository.remove('prof_1', expectedRevision: 4),
      throwsA(isA<StateError>()),
    );
    expect(client.payloads['agentProfile.remove'], isNull);
  });

  test('reorder sends profile ids and unwraps the ordered response', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>[
        aleraRuntimeHostAgentProfileOrderingCapability,
        aleraRuntimeHostAgentProfileRevisionsCapability,
      ],
    };
    client.responses['agentProfile.reorder'] = <String, Object?>{
      'kind': 'agentProfiles',
      'items': <Object?>[
        _profilePayload('prof_2', 'Beta'),
        _profilePayload('prof_1', 'Alpha'),
      ],
    };
    final repository = RuntimeAgentProfileRepository(client);

    final profiles = await repository.reorder(
      <String>['prof_2', 'prof_1'],
      expectedRevisions: <String, int>{'prof_1': 2, 'prof_2': 3},
    );

    expect(profiles.map((profile) => profile.id), <String>['prof_2', 'prof_1']);
    expect(client.payloads['agentProfile.reorder']!.single['ids'], <String>[
      'prof_2',
      'prof_1',
    ]);
    expect(
      client.payloads['agentProfile.reorder']!.single['expectedRevisions'],
      <String, int>{'prof_1': 2, 'prof_2': 3},
    );
  });

  test('reorder refuses an older live host', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': const <String>[],
    };
    final repository = RuntimeAgentProfileRepository(client);

    await expectLater(
      repository.reorder(
        <String>['prof_1'],
        expectedRevisions: <String, int>{'prof_1': 0},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('newer runtime host'),
        ),
      ),
    );
    expect(client.payloads['agentProfile.reorder'], isNull);
  });
}
