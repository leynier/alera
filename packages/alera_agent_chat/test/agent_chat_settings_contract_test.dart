import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

void main() {
  late AgentChatContractTransport transport;
  late RuntimeAgentChatSettingsRepository repository;
  setUp(() {
    transport = AgentChatContractTransport(
      capabilities: <String>{
        AgentChatWire.capability,
        AgentChatWire.preferencesCapability,
        AgentChatWire.providerSettingsCapability,
      },
    );
    repository = RuntimeAgentChatSettingsRepository(transport);
  });
  tearDown(() => transport.controller.close());

  test(
    'preference mutations use canonical entry operations and revision checks',
    () async {
      transport.responses[AgentChatWire.preferencesUpdate] = <String, Object?>{
        'revision': 8,
      };
      final preferences = await repository.updatePreferences(
        const AgentChatPreferencesUpdate(
          requestId: 'r',
          expectedRevision: 7,
          operations: <AgentChatPreferenceOperation>[
            AgentChatSetDefaultSelection(null),
            AgentChatSetProjectDefault(
              projectId: 'p',
              selection: AgentChatSelection(
                providerInstanceId: 'codex',
                model: 'gpt',
              ),
            ),
            AgentChatSetModelPreferences(
              providerInstanceId: 'codex',
              preferences: AgentChatModelPreferences(
                hidden: <String>['hidden'],
                order: <String>['gpt'],
              ),
            ),
            AgentChatSetFavorites(<AgentChatSelection>[
              AgentChatSelection(providerInstanceId: 'codex'),
            ]),
          ],
        ),
        hostId: 'remote',
      );
      expect(preferences.revision, 8);
      expect(transport.requests.single.$1, AgentChatWire.preferencesUpdate);
      expect(transport.requests.single.$2, <String, Object?>{
        'hostId': 'remote',
        'requestId': 'r',
        'expectedRevision': 7,
        'operations': <Object?>[
          <String, Object?>{'type': 'setDefaultSelection', 'selection': null},
          <String, Object?>{
            'type': 'setProjectDefault',
            'projectId': 'p',
            'selection': <String, Object?>{
              'providerInstanceId': 'codex',
              'model': 'gpt',
            },
          },
          <String, Object?>{
            'type': 'setModels',
            'providerInstanceId': 'codex',
            'hidden': <String>['hidden'],
            'order': <String>['gpt'],
          },
          <String, Object?>{
            'type': 'setFavorites',
            'favorites': <Object?>[
              <String, Object?>{'providerInstanceId': 'codex', 'model': null},
            ],
          },
        ],
      });
    },
  );

  test(
    'preferences parse persisted models defaults and remembered selection',
    () async {
      transport.responses[AgentChatWire.preferencesGet] = <String, Object?>{
        'revision': 4,
        'rememberedSelection': <String, Object?>{
          'providerInstanceId': 'codex',
          'model': 'gpt',
        },
        'defaultSelection': null,
        'projectDefaults': <String, Object?>{
          'p': <String, Object?>{
            'providerInstanceId': 'claude',
            'runtimeMode': 'full-access',
          },
        },
        'models': <String, Object?>{
          'codex': <String, Object?>{
            'hidden': <String>['a'],
            'order': <String>['b'],
          },
        },
        'favorites': <Object?>[
          <String, Object?>{'providerInstanceId': 'codex', 'model': null},
        ],
      };
      final result = await repository.preferences(hostId: 'remote');
      expect(result.rememberedSelection?.model, 'gpt');
      expect(
        result.projectDefaults['p']?.runtimeMode,
        AgentChatRuntimeMode.fullAccess,
      );
      expect(result.models['codex']?.hidden, <String>['a']);
      expect(result.favorites.single.model, isNull);
      expect(() => result.projectDefaults.clear(), throwsUnsupportedError);
    },
  );

  test(
    'host catalog refresh carries host and refresh separately from discovery',
    () async {
      await repository.providers(hostId: 'remote', refresh: true);
      expect(transport.requests.single.$1, AgentChatWire.providers);
      expect(transport.requests.single.$2, <String, Object?>{
        'hostId': 'remote',
        'refresh': true,
      });
    },
  );

  test('phone-safe partial settings edits omit launch definitions', () async {
    await repository.upsertProviderInstance(
      requestId: 'r',
      expectedRevision: 2,
      instance: const AgentChatProviderInstanceEdit(
        providerInstanceId: 'codex',
        enabled: false,
        customModels: <String>['gpt'],
        resetDefaultModel: true,
      ),
      hostId: 'remote',
    );
    expect(transport.requests.single.$2, <String, Object?>{
      'requestId': 'r',
      'expectedRevision': 2,
      'hostId': 'remote',
      'instance': <String, Object?>{
        'providerInstanceId': 'codex',
        'enabled': false,
        'customModels': <String>['gpt'],
        'defaultModel': null,
      },
    });
  });

  test('sensitive environment and option values never enter response DTOs', () {
    final envelope = AgentChatProviderInstanceEnvelope.fromJson(
      <String, Object?>{
        'providerInstanceId': 'work',
        'provider': 'codex',
        'environment': <Object?>[
          <String, Object?>{
            'name': 'TOKEN',
            'sensitive': true,
            'value': 'must-not-survive',
            'secretSaved': true,
          },
          <String, Object?>{
            'name': 'REGION',
            'sensitive': false,
            'value': 'eu',
          },
        ],
        'sensitiveOptions': <String>['token'],
        'secretOptions': <Object?>[
          <String, Object?>{'name': 'other', 'secretSaved': true},
        ],
        'options': <String, Object?>{
          'token': 'must-not-survive',
          'other': 'must-not-survive',
          'endpoint': 'localhost',
        },
      },
    );
    expect(envelope.environment.first.value, isNull);
    expect(envelope.environment.first.secretSaved, isTrue);
    expect(envelope.environment.last.value, 'eu');
    expect(envelope.options, <String, Object?>{'endpoint': 'localhost'});
    expect(envelope.secretOptions.single.secretSaved, isTrue);
    final write = envelope.toJson();
    expect(write['sensitiveOptions'], <String>['token']);
    expect(write.containsKey('secretOptions'), isFalse);
    expect(write.containsKey('revision'), isFalse);
    expect((write['environment'] as List).first, <String, Object?>{
      'name': 'TOKEN',
      'sensitive': true,
    });
    expect(
      const AgentChatProviderInstanceEdit(
        providerInstanceId: 'work',
        sensitiveOptions: <String>['token'],
        options: <String, Object?>{
          'token': 'must-not-survive',
          'endpoint': 'localhost',
        },
      ).toJson()['options'],
      <String, Object?>{'endpoint': 'localhost'},
    );
    expect(
      const AgentChatProviderEnvironmentEntry(
        name: 'TOKEN',
        sensitive: true,
        value: 'must-not-survive',
      ).toJson().containsKey('value'),
      isFalse,
    );
  });

  test(
    'secret saves use the separate write-only verb and a declared name',
    () async {
      await repository.setProviderSecret(
        requestId: 'r',
        expectedRevision: 5,
        providerInstanceId: 'work',
        name: 'option:token',
        value: 'test-value',
        hostId: 'remote',
      );
      expect(transport.requests.single.$1, 'agentChat.secrets.set');
      expect(transport.requests.single.$2, <String, Object?>{
        'hostId': 'remote',
        'requestId': 'r',
        'expectedRevision': 5,
        'providerInstanceId': 'work',
        'name': 'option:token',
        'value': 'test-value',
      });
      await repository.clearProviderSecret(
        requestId: 'clear',
        expectedRevision: 6,
        providerInstanceId: 'work',
        name: 'option:token',
      );
      expect(transport.requests.last.$1, 'agentChat.secrets.clear');
      expect(transport.requests.last.$2.containsKey('value'), isFalse);
    },
  );

  test('removal preserves the explicit impact confirmation intent', () async {
    transport.responses[AgentChatWire
        .providerInstancesRemovalImpact] = <String, Object?>{
      'providerInstanceId': 'work',
      'count': 1,
      'openChats': <Object?>[
        <String, Object?>{'chatId': 'c', 'title': 'Chat', 'workspaceId': 'w'},
      ],
    };
    final impact = await repository.providerRemovalImpact(
      providerInstanceId: 'work',
    );
    expect(impact.openChats.single.chatId, 'c');
    await repository.removeProviderInstance(
      requestId: 'r',
      expectedRevision: 2,
      providerInstanceId: 'work',
    );
    expect(transport.requests.last.$2.containsKey('allowInUse'), isFalse);
    await repository.removeProviderInstance(
      requestId: 'confirmed',
      expectedRevision: 2,
      providerInstanceId: 'work',
      allowInUse: true,
    );
    expect(transport.requests.last.$2['allowInUse'], isTrue);
  });

  test('old hosts receive no unknown settings mutation', () async {
    transport.capabilities.clear();
    expect(await repository.preferencesSupported(), isFalse);
    await expectLater(
      repository.preferences(),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    await expectLater(
      repository.providerInstances(),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('settings events carry scope and revisions and reconnect invalidates caches', () async {
    final events = <AgentChatSettingsChanged>[];
    final subscription = repository.watchProviders().listen(events.add);
    transport.controller
      ..add(
        const AgentChatTransportEvent(
          AgentChatWire.providersChangedEvent,
          <String, Object?>{'hostId': 'remote', 'revision': 3},
        ),
      )
      ..add(
        const AgentChatTransportEvent(
          AgentChatTransportEvents.connected,
          <String, Object?>{},
        ),
      );
    await Future.pause(Duration.zero);
    await subscription.cancel();
    expect(
      events.map((event) => (event.hostId, event.revision)),
      <(String?, int?)>[('remote', 3), (null, null)],
    );
  });
}
