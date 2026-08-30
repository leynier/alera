import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
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

class const AgentQuotaSettingsPane({
  super.key,
  required final AgentQuotaSettings settings,
  final Map<String, GlobalKey> groupKeys = const <String, GlobalKey>{},
}) extends ConsumerWidget {
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
      crossAxisAlignment: .stretch,
      children: <Widget>[
        KeyedSubtree(
          key: groupKeys['providers'],
          child: AleraSettingsGroup(
            title: 'Provider Quotas',
            description: 'Choose which usage sources appear for the active workspace host.',
            children: <Widget>[
              AleraSettingRow(
                title: 'Active Quota Host',
                description: 'Run quota commands locally or through the installed Alera runtime for this workspace.',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    hostId == 'local' ? 'Local' : hostId,
                    overflow: .ellipsis,
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
                    secondary: _QuotaPinButton(
                      pinned: hostSettings.isQuotaPinned(provider),
                      enabled: hostSettings.enabledProviders.contains(provider),
                      onChanged: (pinned) {
                        unawaited(
                          controller.setAgentQuotaPinned(
                            hostId: hostId,
                            pinKey: AgentQuotaHostSettings.quotaPinKey(
                              provider,
                            ),
                            pinned: pinned,
                          ),
                        );
                      },
                    ),
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
                description: 'Set the left-to-right order of enabled providers in the status bar.',
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
            description: 'Configure the default Claude account and every CCS profile together.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Claude Code Quotas',
                description: _providerDescription(.claude),
                value: hostSettings.enabledProviders.contains(
                  AgentQuotaProviderId.claude,
                ),
                onChanged: (value) {
                  unawaited(
                    controller.setAgentQuotaProviderEnabled(
                      hostId: hostId,
                      provider: .claude,
                      value: value,
                    ),
                  );
                },
              ),
              SettingsSwitchRow(
                title: 'Claude Default Quotas',
                description: 'Query the default Claude account separately from configured CCS profiles.',
                value: hostSettings.claudeDefaultEnabled,
                secondary: _QuotaPinButton(
                  pinned: hostSettings.isQuotaPinned(.claude),
                  enabled:
                      hostSettings.claudeDefaultEnabled &&
                      hostSettings.enabledProviders.contains(
                        AgentQuotaProviderId.claude,
                      ),
                  onChanged: (pinned) {
                    unawaited(
                      controller.setAgentQuotaPinned(
                        hostId: hostId,
                        pinKey: AgentQuotaHostSettings.quotaPinKey(.claude),
                        pinned: pinned,
                      ),
                    );
                  },
                ),
                onChanged: (value) {
                  unawaited(
                    controller.setClaudeDefaultQuotaEnabled(
                      hostId: hostId,
                      value: value,
                    ),
                  );
                },
              ),
              SettingsSwitchRow(
                title: 'Claude Default in Usage',
                description: 'Include the default Claude account in Usage independently of quota polling.',
                value: hostSettings.claudeDefaultShowInUsage,
                onChanged: (value) {
                  unawaited(
                    controller.setClaudeDefaultShowInUsage(
                      hostId: hostId,
                      value: value,
                    ),
                  );
                },
              ),
              AleraSettingRow(
                title: 'Claude CCS Profiles',
                description:
                    'Add CCS profiles and choose which ones appear in Usage.',
                controlWidth: 420,
                child: _ClaudeProfilesControl(
                  profiles: hostSettings.claudeProfiles,
                  isPinned: (profile) => hostSettings.isQuotaPinned(
                    .claude,
                    claudeAccountId: profile,
                  ),
                  onPinnedChanged: (profile, pinned) {
                    unawaited(
                      controller.setAgentQuotaPinned(
                        hostId: hostId,
                        pinKey: AgentQuotaHostSettings.quotaPinKey(
                          .claude,
                          claudeAccountId: profile,
                        ),
                        pinned: pinned,
                      ),
                    );
                  },
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
            description: 'Configure environment variable names for the active workspace host.',
            children: <Widget>[
              SettingsTextRow(
                key: const ValueKey<String>('kimi-api-key-variable'),
                title: 'Kimi API Key Variable',
                description: 'Environment variable read on the active host. The secret value is never stored by Alera.',
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
                description: 'Environment variable read on the active host. The secret value is never stored by Alera.',
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
                description: 'Optional environment variable for the coding plan API base URL.',
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
                description: 'Environment variable read on the active host. The secret value is never stored by Alera.',
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
                description: 'Optional environment variable selecting the global or china token plan endpoint.',
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
                description: 'Check whether each configured variable exists without reading its secret value.',
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
      'Read default Claude Code usage and any configured CCS profiles.',
    AgentQuotaProviderId.codex =>
      'Read Codex rate limits through the official app server.',
    AgentQuotaProviderId.kimi =>
      'Read Kimi Coding Plan usage with an API key from the host environment.',
    AgentQuotaProviderId.grok =>
      'Read Grok Build usage through its official interactive CLI.',
    AgentQuotaProviderId.cursor =>
      'Read Cursor plan usage from the local Cursor CLI session.',
    AgentQuotaProviderId.antigravity =>
      'Read Antigravity usage through the official agy CLI.',
    AgentQuotaProviderId.minimax => 'Read MiniMax Token Plan usage with an API key from the host environment.',
    AgentQuotaProviderId.zai =>
      'Read Z.ai limits with an API key from the host environment.',
    AgentQuotaProviderId.opencode => 'Estimate OpenCode Go quota and local OpenCode Zen spend from the host database.',
  };
}

class const _EnvironmentPresence({
  required final List<String> names,
  required final Map<String, bool> presence,
  required final bool loading,
  required final VoidCallback onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
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
                    overflow: .ellipsis,
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
