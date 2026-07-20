import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_provider_icon.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'agent_quota_settings_controls.dart';

class AgentQuotaSettingsPane extends ConsumerWidget {
  const AgentQuotaSettingsPane({
    super.key,
    required this.settings,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final AgentQuotaSettings settings;
  final Map<String, GlobalKey> groupKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostId = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.activeWorkspace?.hostId ?? 'local',
      ),
    );
    final hostSettings = settings.forHost(hostId);
    final quotaState = ref.watch(agentQuotaStateProvider);
    final environment = quotaState.value?.hostId == hostId
        ? quotaState.value?.environment ?? const <String, bool>{}
        : const <String, bool>{};
    final controller = ref.read(settingsControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: groupKeys['providers'],
          child: AleraSettingsGroup(
            title: 'Provider Quotas',
            description:
                'Choose Which Usage Sources Appear For The Active Workspace Host.',
            children: <Widget>[
              AleraSettingRow(
                title: 'Active Quota Host',
                description:
                    'Run Quota Commands Locally Or Through The Installed Alera Runtime For This Workspace.',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    hostId == 'local' ? 'Local' : hostId,
                    overflow: TextOverflow.ellipsis,
                    style: AleraTokens.monoStyle,
                  ),
                ),
              ),
              for (final provider in AgentQuotaProviderId.values)
                if (provider != AgentQuotaProviderId.claude)
                  SettingsSwitchRow(
                    title: '${provider.label} Quotas',
                    description: _providerDescription(provider),
                    value: hostSettings.enabledProviders.contains(provider),
                    onChanged: (value) {
                      unawaited(
                        controller.setAgentQuotaProviderEnabled(
                          hostId: hostId,
                          provider: provider,
                          value: value,
                        ),
                      );
                    },
                  ),
              AleraSettingRow(
                title: 'Quota Display Order',
                description:
                    'Set The Left-To-Right Order Of Enabled Providers In The Status Bar.',
                controlWidth: 420,
                child: _ProviderOrderControl(
                  providers: hostSettings.enabledProviders,
                  onChanged: (providers) {
                    unawaited(
                      controller.setAgentQuotaProviderOrder(
                        hostId: hostId,
                        providers: providers,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['claude'],
          child: AleraSettingsGroup(
            title: 'Claude',
            description:
                'Configure The Default Claude Account And Every CCS Profile Together.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Claude Code Quotas',
                description: _providerDescription(AgentQuotaProviderId.claude),
                value: hostSettings.enabledProviders.contains(
                  AgentQuotaProviderId.claude,
                ),
                onChanged: (value) {
                  unawaited(
                    controller.setAgentQuotaProviderEnabled(
                      hostId: hostId,
                      provider: AgentQuotaProviderId.claude,
                      value: value,
                    ),
                  );
                },
              ),
              SettingsSwitchRow(
                title: 'Claude Default Quotas',
                description:
                    'Query The Default Claude Account Separately From Configured CCS Profiles.',
                value: hostSettings.claudeDefaultEnabled,
                onChanged: (value) {
                  unawaited(
                    controller.setClaudeDefaultQuotaEnabled(
                      hostId: hostId,
                      value: value,
                    ),
                  );
                },
              ),
              AleraSettingRow(
                title: 'Claude CCS Profiles',
                description:
                    'Add CCS Alias And Profile Pairs. These Remain Available When Default Claude Is Disabled.',
                controlWidth: 420,
                child: _ClaudeProfilesControl(
                  profiles: hostSettings.claudeProfiles,
                  onChanged: (profiles) {
                    unawaited(
                      controller.setClaudeQuotaProfiles(
                        hostId: hostId,
                        profiles: profiles,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['credentials'],
          child: AleraSettingsGroup(
            title: 'Credential Environment',
            description:
                'Configure Environment Variable Names For The Active Workspace Host.',
            children: <Widget>[
              SettingsTextRow(
                key: const ValueKey<String>('kimi-api-key-variable'),
                title: 'Kimi API Key Variable',
                description:
                    'Environment Variable Read On The Active Host. The Secret Value Is Never Stored By Alera.',
                value: hostSettings.environment.kimiApiKey,
                hintText: 'KIMI_API_KEY',
                onChanged: (value) => _saveEnvironment(
                  controller,
                  hostId,
                  hostSettings.environment.copyWith(kimiApiKey: value),
                ),
              ),
              SettingsTextRow(
                title: 'Z.ai API Key Variable',
                description:
                    'Environment Variable Read On The Active Host. The Secret Value Is Never Stored By Alera.',
                value: hostSettings.environment.zaiApiKey,
                hintText: 'ZAI_API_KEY',
                onChanged: (value) => _saveEnvironment(
                  controller,
                  hostId,
                  hostSettings.environment.copyWith(zaiApiKey: value),
                ),
              ),
              SettingsTextRow(
                title: 'Z.ai Base URL Variable',
                description:
                    'Optional Environment Variable For The Coding Plan API Base URL.',
                value: hostSettings.environment.zaiBaseUrl,
                hintText: 'ZAI_BASE_URL',
                onChanged: (value) => _saveEnvironment(
                  controller,
                  hostId,
                  hostSettings.environment.copyWith(zaiBaseUrl: value),
                ),
              ),
              SettingsTextRow(
                title: 'MiniMax API Key Variable',
                description:
                    'Environment Variable Read On The Active Host. The Secret Value Is Never Stored By Alera.',
                value: hostSettings.environment.minimaxApiKey,
                hintText: 'MINIMAX_API_KEY',
                onChanged: (value) => _saveEnvironment(
                  controller,
                  hostId,
                  hostSettings.environment.copyWith(minimaxApiKey: value),
                ),
              ),
              SettingsTextRow(
                title: 'MiniMax API Host Variable',
                description:
                    'Optional Environment Variable Selecting The Global Or China Token Plan Endpoint.',
                value: hostSettings.environment.minimaxApiHost,
                hintText: 'MINIMAX_API_HOST',
                onChanged: (value) => _saveEnvironment(
                  controller,
                  hostId,
                  hostSettings.environment.copyWith(minimaxApiHost: value),
                ),
              ),
              AleraSettingRow(
                title: 'Credential Availability',
                description:
                    'Check Whether Each Configured Variable Exists Without Reading Its Secret Value.',
                controlWidth: 420,
                child: _EnvironmentPresence(
                  names: <String>[
                    hostSettings.environment.kimiApiKey,
                    hostSettings.environment.zaiApiKey,
                    hostSettings.environment.zaiBaseUrl,
                    hostSettings.environment.minimaxApiKey,
                    hostSettings.environment.minimaxApiHost,
                  ],
                  presence: environment,
                  loading: quotaState.isLoading,
                  onRefresh: () {
                    ref
                        .read(agentQuotaServiceProvider)
                        .requestForceRefresh(hostId);
                    ref.invalidate(agentQuotaStateProvider);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _saveEnvironment(
  SettingsController controller,
  String hostId,
  AgentQuotaEnvironmentSettings environment,
) {
  unawaited(
    controller.setAgentQuotaEnvironment(
      hostId: hostId,
      environment: environment,
    ),
  );
}

String _providerDescription(AgentQuotaProviderId provider) {
  return switch (provider) {
    AgentQuotaProviderId.claude =>
      'Read Default Claude Code Usage And Any Configured CCS Profiles.',
    AgentQuotaProviderId.codex =>
      'Read Codex Rate Limits Through The Official App Server.',
    AgentQuotaProviderId.kimi =>
      'Read Kimi Coding Plan Usage With An API Key From The Host Environment.',
    AgentQuotaProviderId.grok =>
      'Read Grok Build Usage Through Its Official Interactive CLI.',
    AgentQuotaProviderId.antigravity =>
      'Read Antigravity Usage Through The Official Agy CLI.',
    AgentQuotaProviderId.minimax =>
      'Read MiniMax Token Plan Usage With An API Key From The Host Environment.',
    AgentQuotaProviderId.zai =>
      'Read Z.ai Limits With An API Key From The Host Environment.',
  };
}

class _EnvironmentPresence extends StatelessWidget {
  const _EnvironmentPresence({
    required this.names,
    required this.presence,
    required this.loading,
    required this.onRefresh,
  });

  final List<String> names;
  final Map<String, bool> presence;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final name in names)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
            child: Row(
              children: <Widget>[
                Icon(
                  presence[name] == true ? AleraIcons.check : AleraIcons.close,
                  size: 13,
                  color: presence[name] == true
                      ? AleraTokens.success
                      : AleraTokens.foregroundFaint,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: AleraTokens.monoStyle,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AleraTokens.space6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: Icon(
              loading ? AleraIcons.loading : AleraIcons.refresh,
              size: 14,
            ),
            label: const Text('Check Environment'),
          ),
        ),
      ],
    );
  }
}
