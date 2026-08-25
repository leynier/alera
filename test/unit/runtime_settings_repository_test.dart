import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/runtime_settings_repository.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

final class _RecordingRuntimeHostClient implements RuntimeHostClient {
  final payloads = <String, List<Map<String, Object?>>>{};
  final responses = <String, Object?>{};

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
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
