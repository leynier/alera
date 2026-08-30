import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/runtime_settings_repository.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'portable runtime values refresh the cache without exporting local paths',
    () async {
      final legacy = _MemorySettingsRepository();
      final client = _RecordingRuntimeHostClient()
        ..configurationSupported = true;
      client.responses['configuration.settings.get'] = {
        'terminal': {'fontSize': 19.0},
        'general': {'workspaceDirectory': '/remote/path'},
      };
      client.responses['runtimeSettings.get'] = {
        'workspaceDirectory': '/local/path',
      };
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: legacy,
      );
      final result = await repository.load();
      expect(result.terminal.fontSize, 19);
      expect(result.general.workspaceDirectory, '/local/path');
      expect(legacy.settings.terminal.fontSize, 19);
      final seed =
          client.payloads['configuration.settings.seed']!.single['settings']!
              as Map;
      expect(seed['general'], isNot(contains('workspaceDirectory')));
      expect(seed['agents'], isNot(contains('quotas')));
      await repository.save(result);
      expect(client.payloads['configuration.settings.update'], hasLength(1));
    },
  );
  test(
    'a failed runtime save leaves the compatibility cache unchanged',
    () async {
      final legacy = _MemorySettingsRepository();
      final client = _RecordingRuntimeHostClient()
        ..configurationSupported = true
        ..failConfigurationUpdate = true;
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: legacy,
      );
      final original = legacy.settings;
      await expectLater(
        repository.save(
          original.copyWith(terminal: original.terminal.copyWith(fontSize: 21)),
        ),
        throwsStateError,
      );
      expect(legacy.settings, original);
      expect(client.payloads, isNot(contains('runtimeSettings.update')));
    },
  );
  test(
    'RuntimeSettingsRepository sends structured portable settings',
    () async {
      final client = _RecordingRuntimeHostClient();
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: _MemorySettingsRepository(),
      );

      await repository.save(
        AleraSettings.defaults.copyWith(
          aiAssist: const AiAssistSettings(
            selectedThinkingByOperation:
                <AiAssistOperation, Map<String, String>>{
                  AiAssistOperation.commitMessage: <String, String>{
                    'gpt-5.5': 'high',
                  },
                },
          ),
        ),
      );

      final payload = client.payloads['runtimeSettings.update']!.single;
      expect(payload['agentStatusHooks'], isA<Map<String, Object?>>());
      expect(payload['agentQuotas'], isA<Map<String, Object?>>());
      expect(payload['defaultAgentProfileId'], isNull);
      expect(payload['aiTextGeneration'], isA<Map<String, Object?>>());
      final aiAssist = payload['aiTextGeneration']! as Map<String, Object?>;
      expect(aiAssist['agent'], 'codex');
      expect(
        aiAssist['promptSettingsByOperation'],
        isA<Map<String, Object?>>(),
      );
      expect(aiAssist['selectedThinkingByOperation'], <String, Object?>{
        'commitMessage': <String, String>{'gpt-5.5': 'high'},
      });
      expect(aiAssist, isNot(contains('discoveredModelsByAgent')));
      expect(
        (payload['agentQuotas']! as Map<String, Object?>)['enabledProviders'],
        <String>[
          'claude',
          'codex',
          'kimi',
          'grok',
          'cursor',
          'antigravity',
          'minimax',
          'zai',
          'opencode',
        ],
      );
    },
  );

  test(
    'load preserves UI-only quota fields the runtime does not store',
    () async {
      final legacyRepository = _MemorySettingsRepository();
      legacyRepository.settings = AleraSettings.defaults.copyWith(
        agents: AleraSettings.defaults.agents.copyWith(
          quotas: AgentQuotaSettings.defaults.withHost(
            'local',
            const AgentQuotaHostSettings(
              selectedClaudeProfile: 'leynierdev',
              unpinnedQuotaKeys: <String>['codex', 'claude:leynierdev'],
            ),
          ),
        ),
      );
      final client = _RecordingRuntimeHostClient();
      client.responses['runtimeSettings.get'] = <String, Object?>{
        'workspaceDirectory': '/tmp/workspaces',
        'defaultAgentProfileId': 'prof_2',
        'agentQuotas': <String, Object?>{
          'enabledProviders': <String>['claude', 'codex'],
          'claudeDefaultEnabled': false,
        },
      };
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: legacyRepository,
      );

      final loaded = await repository.load();
      final local = loaded.agents.quotas.forHost('local');

      expect(loaded.agents.defaultAgentProfileId, 'prof_2');
      expect(local.enabledProviders, <AgentQuotaProviderId>[
        AgentQuotaProviderId.claude,
        AgentQuotaProviderId.codex,
      ]);
      expect(local.claudeDefaultEnabled, isFalse);
      expect(local.claudeDefaultShowInUsage, isTrue);
      expect(local.selectedClaudeProfile, 'leynierdev');
      expect(local.unpinnedQuotaKeys, <String>['codex', 'claude:leynierdev']);
    },
  );

  test('save sends the selected default agent profile', () async {
    final client = _RecordingRuntimeHostClient();
    final repository = RuntimeSettingsRepository(
      client: client,
      legacyRepository: _MemorySettingsRepository(),
    );
    final settings = AleraSettings.defaults.copyWith(
      agents: AleraSettings.defaults.agents.copyWith(
        defaultAgentProfileId: 'prof_2',
      ),
    );

    await repository.save(settings);

    expect(
      client
          .payloads['runtimeSettings.update']!
          .single['defaultAgentProfileId'],
      'prof_2',
    );
  });

  test(
    'load combines shared AI Assist execution settings with local discovery',
    () async {
      final legacyRepository = _MemorySettingsRepository();
      legacyRepository.settings = AleraSettings.defaults.copyWith(
        aiAssist: const AiAssistSettings(
          discoveredModelsByAgent:
              <AiAssistAgent, List<AiAssistDiscoveredModel>>{
                AiAssistAgent.codex: <AiAssistDiscoveredModel>[
                  AiAssistDiscoveredModel(
                    id: 'local-model',
                    label: 'Local Model',
                  ),
                ],
              },
        ),
      );
      final client = _RecordingRuntimeHostClient();
      client.responses['runtimeSettings.get'] = <String, Object?>{
        'workspaceDirectory': '/tmp/workspaces',
        'aiTextGeneration': <String, Object?>{
          'enabled': true,
          'agent': 'claude',
          'selectedModelByAgent': <String, String>{'claude': 'opus'},
          'selectedThinkingByOperation': <String, Object?>{
            'workspaceIdentity': <String, String>{'opus': 'high'},
          },
          'instructionsByOperation': <String, String>{
            'workspaceIdentity': 'Use feature branches.',
          },
          'promptSettingsByOperation': <String, Object?>{
            'workspaceIdentity': <String, Object?>{
              'agent': 'claude',
              'model': 'opus',
            },
          },
          'timeoutSeconds': 180,
        },
      };
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: legacyRepository,
      );

      final loaded = await repository.load();

      expect(loaded.aiAssist.agent, AiAssistAgent.claude);
      expect(
        loaded.aiAssist.instructionsFor(AiAssistOperation.workspaceIdentity),
        'Use feature branches.',
      );
      expect(
        loaded.aiAssist.agentFor(AiAssistOperation.workspaceIdentity),
        AiAssistAgent.claude,
      );
      expect(
        loaded.aiAssist.modelForOperation(AiAssistOperation.workspaceIdentity),
        'opus',
      );
      expect(
        loaded.aiAssist.thinkingForOperation(
          AiAssistOperation.workspaceIdentity,
          'opus',
        ),
        'high',
      );
      expect(
        loaded.aiAssist.discoveredModelsFor(AiAssistAgent.codex).single.id,
        'local-model',
      );
    },
  );

  test(
    'saves and loads text actions while older hosts fall back locally',
    () async {
      final legacyRepository = _MemorySettingsRepository();
      final action = const TextAction(
        id: 'polish',
        name: 'Polish',
        prompt: 'Improve the selected text.',
      );
      final client = _RecordingRuntimeHostClient();
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: legacyRepository,
      );

      await repository.save(
        AleraSettings.defaults.copyWith(
          textActions: TextActionsSettings(actions: <TextAction>[action]),
        ),
      );
      final payload = client.payloads['runtimeSettings.update']!.single;
      expect(payload['textActions'], <String, Object?>{
        'actions': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'polish',
            'name': 'Polish',
            'prompt': 'Improve the selected text.',
            'enabled': true,
            'agentOverride': null,
            'modelOverride': null,
            'reasoningByModel': <String, String>{},
          },
        ],
      });

      legacyRepository.settings = AleraSettings.defaults.copyWith(
        textActions: TextActionsSettings(actions: <TextAction>[action]),
      );
      client.responses['runtimeSettings.get'] = <String, Object?>{
        'workspaceDirectory': '/tmp/workspaces',
      };
      final loadedFromOldHost = await repository.load();
      expect(loadedFromOldHost.textActions.actions.single.id, 'polish');

      client.responses['runtimeSettings.get'] = <String, Object?>{
        'workspaceDirectory': '/tmp/workspaces',
        'textActions': <String, Object?>{'actions': <Object?>[]},
      };
      final loadedFromNewHost = await repository.load();
      expect(loadedFromNewHost.textActions.actions, isEmpty);
    },
  );
  test('restoring absent portable settings uses defaults and preserves local fields', () async {
    final client = _RecordingRuntimeHostClient()..configurationSupported = true;
    final legacy = _MemorySettingsRepository();
    legacy.settings = AleraSettings.defaults.copyWith(
      terminal: AleraSettings.defaults.terminal.copyWith(
        fontSize: 20,
        scrollbackLines: 1234,
      ),
      general: AleraSettings.defaults.general.copyWith(
        workspaceDirectory: '/local',
      ),
    );
    client.responses['configuration.settings.get'] = <String, Object?>{
      'terminal': <String, Object?>{},
    };
    client.responses['runtimeSettings.get'] = <String, Object?>{
      'workspaceDirectory': '/local',
    };
    final actual = await RuntimeSettingsRepository(
      client: client,
      legacyRepository: legacy,
    ).load();
    expect(actual.terminal.fontSize, AleraSettings.defaults.terminal.fontSize);
    expect(actual.terminal.scrollbackLines, 1234);
    expect(actual.general.workspaceDirectory, '/local');
  });
  test(
    'unknown shortcuts do not prevent known portable preferences loading',
    () async {
      final client = _RecordingRuntimeHostClient()
        ..configurationSupported = true;
      final legacy = _MemorySettingsRepository();
      client.responses['configuration.settings.get'] = {
        'terminal': {'fontSize': 20},
        'keyboard': {
          'overrides': {
            'openSettings': ['Mod+Comma'],
            'futureAction': ['Mod+F12'],
          },
        },
      };
      client.responses['runtimeSettings.get'] = {'workspaceDirectory': null};
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: legacy,
      );
      final actual = await repository.load();
      expect(actual.terminal.fontSize, 20);
      expect(actual.keyboard.overrides.keys.map((id) => id.name), [
        'openSettings',
      ]);
      await repository.save(actual);
      final saved = client.payloads['configuration.settings.update']!.single;
      expect(saved['supportedKeyboardActionIds'], contains('openSettings'));
      expect(
        saved['supportedKeyboardActionIds'],
        isNot(contains('futureAction')),
      );
    },
  );
}

final class _RecordingRuntimeHostClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  final payloads = <String, List<Map<String, Object?>>>{};
  final responses = <String, Object?>{};
  bool configurationSupported = false;
  bool failConfigurationUpdate = false;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      configurationSupported && capability == 'configurationSyncV1';

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    if (type == 'configuration.settings.update' && failConfigurationUpdate) {
      throw StateError('Runtime unavailable');
    }
    return responses[type];
  }
}

final class _MemorySettingsRepository implements SettingsRepository {
  AleraSettings settings = AleraSettings.defaults;

  @override
  Future<AleraSettings> load() async => settings;

  @override
  Future<void> save(AleraSettings settings) async {
    this.settings = settings;
  }
}
