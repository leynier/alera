import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
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
    var legacy = await legacyRepository.load();
    try {
      await beforeAccess?.call();
      if (await _supportsConfiguration()) {
        await client.runtimeRequest('configuration.settings.seed', {
          'settings': portableDesktopSettings(legacy.toMap()),
        });
        final portable = jsonMap(
          await client.runtimeRequest('configuration.settings.get'),
        );
        final keyboard = jsonMap(portable['keyboard']);
        keyboard['overrides'] = jsonMap(keyboard['overrides'])
          ..removeWhere(
            (key, _) => !KeyboardActionId.values.any((id) => id.name == key),
          );
        portable['keyboard'] = keyboard;
        legacy = AleraSettings.fromJson(
          applyDesktopSettings(
            legacy.toMap(),
            portable,
            defaults: AleraSettings.defaults.toMap(),
          ),
        );
      }
      final payload = await client.runtimeRequest('runtimeSettings.get');
      final runtime = _asMap(payload);
      if (!runtime.containsKey('workspaceDirectory')) {
        return legacy;
      }
      final legacyLocalQuotas = legacy.agents.quotas.forHost('local');
      final runtimeAiAssist = _asMap(runtime['aiTextGeneration']);
      final sharedAiAssist = runtimeAiAssist.isEmpty
          ? legacy.aiAssist
          : AiAssistSettings.fromJson(runtimeAiAssist).copyWith(
              discoveredModelsByAgent: legacy.aiAssist.discoveredModelsByAgent,
              discoveredDefaultModelByAgent:
                  legacy.aiAssist.discoveredDefaultModelByAgent,
            );
      final runtimeTextActions = _asMap(runtime['textActions']);
      final sharedTextActions = runtimeTextActions.isEmpty
          ? legacy.textActions
          : TextActionsSettings.fromJson(runtimeTextActions);
      final defaultAgentProfileId = runtime.containsKey('defaultAgentProfileId')
          ? _optionalRuntimeString(runtime['defaultAgentProfileId'])
          : legacy.agents.defaultAgentProfileId;
      final resolved = legacy.copyWith(
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
          defaultAgentProfileId: defaultAgentProfileId,
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
        aiAssist: sharedAiAssist,
        textActions: sharedTextActions,
      );
      await legacyRepository.save(resolved);
      return resolved;
    } catch (_) {
      return legacy;
    }
  }

  @override
  Future<void> save(AleraSettings settings) async {
    await beforeAccess?.call();
    if (await _supportsConfiguration()) {
      await client.runtimeRequest('configuration.settings.update', {
        'settings': portableDesktopSettings(settings.toMap()),
        'supportedKeyboardActionIds': KeyboardActionId.values
            .map((id) => id.name)
            .toList(),
      });
    }
    await client.runtimeRequest('runtimeSettings.update', <String, Object?>{
      'workspaceDirectory': settings.general.workspaceDirectory,
      'confirmProjectRemoval': settings.general.confirmProjectRemoval,
      'confirmWorkspaceRemoval': settings.general.confirmWorkspaceRemoval,
      'defaultAgentProfileId': settings.agents.defaultAgentProfileId,
      'agentStatusHooks': settings.agents.agentStatusHooks.toMap(),
      'agentQuotas': settings.agents.quotas.forHost('local').toMap(),
      'aiTextGeneration': _runtimeAiAssistSettings(settings.aiAssist),
      'textActions': settings.textActions.toMap(),
    });
    await legacyRepository.save(settings);
  }

  Future<bool> _supportsConfiguration() async {
    final capabilityClient = client;
    return capabilityClient is RuntimeHostCapabilityClient &&
        await (capabilityClient as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability('configurationSyncV1');
  }
}

Map<String, Object?> _runtimeAiAssistSettings(AiAssistSettings settings) {
  return <String, Object?>{
    'enabled': settings.enabled,
    'autoGenerateAgentTitles': settings.autoGenerateAgentTitles,
    'agent': settings.agent.key,
    'selectedModelByAgent': <String, String>{
      for (final entry in settings.selectedModelByAgent.entries)
        entry.key.key: entry.value,
    },
    'selectedThinkingByModel': settings.selectedThinkingByModel,
    'selectedThinkingByOperation': <String, Map<String, String>>{
      for (final entry in settings.selectedThinkingByOperation.entries)
        entry.key.key: entry.value,
    },
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

String? _optionalRuntimeString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}
