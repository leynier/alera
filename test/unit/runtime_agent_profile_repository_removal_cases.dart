part of 'runtime_agent_profile_repository_test.dart';

void _registerAgentProfileRemovalRepositoryTests() {
  test('removal impact defaults absent owner collections to empty', () {
    final impact = AgentProfileRemovalImpact.fromJson(<String, Object?>{
      'profileId': 'prof_1',
      'exists': true,
    });

    expect(impact.automationIds, isEmpty);
    expect(impact.executionPolicyRunIds, isEmpty);
    expect(impact.tabs, isEmpty);
    expect(impact.hasBlockingReferences, isFalse);
    expect(
      impact.removalMessage('Codex'),
      'Codex has no references. Deleting it cannot be undone.',
    );
  });

  test('removal impact explains references cleared with deletion', () {
    const impact = AgentProfileRemovalImpact(
      profileId: 'prof_1',
      exists: true,
      isDefault: true,
      automationIds: <String>[],
      hasAutomationPolicy: true,
      executionPolicyRunIds: <String>[],
      tabs: <AgentProfileTabReference>[],
    );

    expect(impact.hasBlockingReferences, isFalse);
    expect(
      impact.removalMessage('Codex'),
      'Codex is referenced by the default profile setting, an automation policy. '
      'These references will be cleared atomically when the profile is deleted.',
    );
  });

  test('removal impact parses safe owner identities', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>[
        aleraRuntimeHostAgentProfileRevisionsCapability,
        aleraRuntimeHostAgentProfileRemovalCapability,
      ],
    };
    client.responses['agentProfile.removalImpact'] = <String, Object?>{
      'profileId': 'prof_1',
      'exists': true,
      'revision': 7,
      'isDefault': true,
      'automationIds': <String>['automation-1'],
      'hasAutomationPolicy': true,
      'executionPolicyRunIds': <String>['run-1'],
      'tabs': <Object?>[
        <String, Object?>{'workspaceId': 'workspace-1', 'tabId': 'tab-1'},
      ],
    };
    final repository = RuntimeAgentProfileRepository(client);

    final impact = await repository.removalImpact(
      'prof_1',
      expectedRevision: 7,
    );

    expect(impact.hasBlockingReferences, isTrue);
    expect(impact.automationIds, <String>['automation-1']);
    expect(impact.executionPolicyRunIds, <String>['run-1']);
    expect(impact.tabs.single.tabId, 'tab-1');
    expect(
      impact.removalMessage('Codex'),
      'Codex is referenced by 1 automation, 1 tab, the default profile setting, '
      'an automation policy, 1 active execution policy. Remove its automation '
      'and tab references before deleting it.',
    );
    expect(
      client.payloads['agentProfile.removalImpact']!.single,
      <String, Object?>{'id': 'prof_1', 'expectedRevision': 7},
    );
  });

  test('remove sends explicit confirmation', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': <String>[
        aleraRuntimeHostAgentProfileRevisionsCapability,
        aleraRuntimeHostAgentProfileRemovalCapability,
      ],
    };
    client.responses['agentProfile.remove'] = <String, Object?>{
      'removed': true,
    };
    final repository = RuntimeAgentProfileRepository(client);

    await repository.remove('prof_1', expectedRevision: 7, confirmed: true);

    expect(client.payloads['agentProfile.remove']!.single, <String, Object?>{
      'id': 'prof_1',
      'expectedRevision': 7,
      'confirmed': true,
    });
  });

  test('removal impact refuses an older live host', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': const <String>[],
    };
    final repository = RuntimeAgentProfileRepository(client);

    await expectLater(
      repository.removalImpact('prof_1', expectedRevision: 7),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('newer runtime host'), contains('Restart Alera')),
        ),
      ),
    );
    expect(client.payloads['agentProfile.removalImpact'], isNull);
  });

  test('remove refuses an older live host without falling back', () async {
    final client = _FakeRuntimeHostClient();
    client.responses['status.get'] = <String, Object?>{
      'runtimeCapabilities': const <String>[],
    };
    final repository = RuntimeAgentProfileRepository(client);

    await expectLater(
      repository.remove('prof_1', expectedRevision: 7, confirmed: true),
      throwsA(isA<StateError>()),
    );
    expect(client.payloads['agentProfile.remove'], isNull);
  });
}
