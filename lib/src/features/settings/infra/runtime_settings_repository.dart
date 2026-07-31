import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeSettingsRepository implements SettingsRepository {
  RuntimeSettingsRepository({
    required this.client,
    required this.legacyRepository,
    this.beforeAccess,
  });

  final RuntimeHostClient client;
  final SettingsRepository legacyRepository;
  final Future<void> Function()? beforeAccess;

  @override
  Future<AleraSettings> load() async {
    final legacy = await legacyRepository.load();
    try {
      await beforeAccess?.call();
      final payload = await client.runtimeRequest('runtimeSettings.get');
      final runtime = _asMap(payload);
      if (!runtime.containsKey('workspaceDirectory')) {
        return legacy;
      }
      final legacyLocalQuotas = legacy.agents.quotas.forHost('local');
      final runtimeAiText = _asMap(runtime['aiTextGeneration']);
      final sharedAiText = runtimeAiText.isEmpty
          ? legacy.aiTextGeneration
          : AiTextGenerationSettings.fromJson(runtimeAiText).copyWith(
              discoveredModelsByAgent:
                  legacy.aiTextGeneration.discoveredModelsByAgent,
              discoveredDefaultModelByAgent:
                  legacy.aiTextGeneration.discoveredDefaultModelByAgent,
            );
      return legacy.copyWith(
        general: legacy.general.copyWith(
          workspaceDirectory: runtime['workspaceDirectory'] as String?,
          confirmProjectRemoval:
              runtime['confirmProjectRemoval'] as bool? ??
              legacy.general.confirmProjectRemoval,
          confirmWorkspaceRemoval:
              runtime['confirmWorkspaceRemoval'] as bool? ??
              legacy.general.confirmWorkspaceRemoval,
        ),
        agents: legacy.agents.copyWith(
          agentStatusHooks: AgentStatusHookSettings.fromJson(
            _asMap(runtime['agentStatusHooks']),
          ),
          quotas: legacy.agents.quotas.withHost(
            'local',
            // The runtime host stores only the quota fields it needs to fetch
            // usage, so UI-only fields must survive the merge from the local
            // repository or every runtimeSettingsChanged event resets them.
            AgentQuotaHostSettings.fromJson(
              _asMap(runtime['agentQuotas']),
            ).copyWith(
              selectedClaudeProfile: legacyLocalQuotas.selectedClaudeProfile,
              unpinnedQuotaKeys: legacyLocalQuotas.unpinnedQuotaKeys,
            ),
          ),
        ),
        aiTextGeneration: sharedAiText,
      );
    } catch (_) {
      return legacy;
    }
  }

  @override
  Future<void> save(AleraSettings settings) async {
    await legacyRepository.save(settings);
    await beforeAccess?.call();
    await client.runtimeRequest('runtimeSettings.update', <String, Object?>{
      'workspaceDirectory': settings.general.workspaceDirectory,
      'confirmProjectRemoval': settings.general.confirmProjectRemoval,
      'confirmWorkspaceRemoval': settings.general.confirmWorkspaceRemoval,
      'agentStatusHooks': settings.agents.agentStatusHooks.toMap(),
      'agentQuotas': settings.agents.quotas.forHost('local').toMap(),
      'aiTextGeneration': _runtimeAiTextSettings(settings.aiTextGeneration),
    });
  }
}

Map<String, Object?> _runtimeAiTextSettings(AiTextGenerationSettings settings) {
  return <String, Object?>{
    'enabled': settings.enabled,
    'agent': settings.agent.key,
    'selectedModelByAgent': <String, String>{
      for (final entry in settings.selectedModelByAgent.entries)
        entry.key.key: entry.value,
    },
    'selectedThinkingByModel': settings.selectedThinkingByModel,
    'customCommand': settings.customCommand,
    'instructionsByOperation': <String, String>{
      for (final entry in settings.instructionsByOperation.entries)
        entry.key.key: entry.value,
    },
    'promptSettingsByOperation': <String, Map<String, Object?>>{
      for (final entry in settings.promptSettingsByOperation.entries)
        entry.key.key: <String, Object?>{
          if (entry.value.agent != null) 'agent': entry.value.agent!.key,
          if (entry.value.model?.trim().isNotEmpty == true)
            'model': entry.value.model!.trim(),
        },
    },
    'timeoutSeconds': settings.timeoutSeconds,
  };
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}
