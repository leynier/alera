import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/quotas/application/agent_quota_controller.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/quotas/presentation/claude_quota_profile_dialog.dart';
import 'package:alera_mobile/src/features/settings/application/host_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuotaSettingsScreen extends ConsumerWidget {
  const QuotaSettingsScreen({super.key, required this.host});

  final PairedHostProfile host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostSettings = ref.watch(hostSettingsControllerProvider(host.id));
    final quotaState = ref.watch(agentQuotaControllerProvider(host.id)).value;
    final settingsValue = hostSettings.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Configure Quotas')),
      body: SafeArea(
        child: settingsValue != null
            ? _QuotaSettingsBody(
                hostId: host.id,
                settings: settingsValue.agentQuotas,
                environmentPresence:
                    quotaState?.environment ?? const <String, bool>{},
              )
            : hostSettings.hasError
            ? Center(child: Text(hostSettings.error.toString()))
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _QuotaSettingsBody extends ConsumerWidget {
  const _QuotaSettingsBody({
    required this.hostId,
    required this.settings,
    required this.environmentPresence,
  });

  final String hostId;
  final QuotaSettings settings;
  final Map<String, bool> environmentPresence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      hostSettingsControllerProvider(hostId).notifier,
    );
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        _SectionTitle(
          title: 'Providers',
          description: 'Choose sources and their display order.',
        ),
        Card(
          child: Column(
            children: <Widget>[
              for (final provider in supportedQuotaProviders)
                SwitchListTile(
                  value: settings.enabledProviders.contains(provider),
                  onChanged: (enabled) {
                    final providers = settings.enabledProviders.toList();
                    if (enabled) {
                      if (!providers.contains(provider)) {
                        providers.add(provider);
                      }
                    } else {
                      providers.remove(provider);
                    }
                    controller.updateQuotas(
                      settings.copyWith(enabledProviders: providers),
                    );
                  },
                  title: Text('${quotaProviderLabels[provider]} Quotas'),
                ),
              if (settings.enabledProviders.isNotEmpty) const Divider(),
              for (final (index, provider) in settings.enabledProviders.indexed)
                ListTile(
                  title: Text(quotaProviderLabels[provider] ?? provider),
                  subtitle: const Text('Display order'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Move Earlier',
                        onPressed: index == 0
                            ? null
                            : () => controller.updateQuotas(
                                settings.copyWith(
                                  enabledProviders: _move(
                                    settings.enabledProviders,
                                    index,
                                    -1,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Move Later',
                        onPressed: index == settings.enabledProviders.length - 1
                            ? null
                            : () => controller.updateQuotas(
                                settings.copyWith(
                                  enabledProviders: _move(
                                    settings.enabledProviders,
                                    index,
                                    1,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        _SectionTitle(
          title: 'Claude',
          description: 'Default account and ordered CCS profiles.',
        ),
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                value: settings.claudeDefaultEnabled,
                onChanged: (value) => controller.updateQuotas(
                  settings.copyWith(claudeDefaultEnabled: value),
                ),
                title: const Text('Claude Default Quotas'),
              ),
              for (final (index, profile) in settings.claudeProfiles.indexed)
                ListTile(
                  title: Text(profile.alias),
                  subtitle: Text(
                    profile.profile,
                    style: const TextStyle(
                      fontFamily: AleraTokens.monoFontFamily,
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _handleProfileAction(
                      context,
                      controller,
                      settings,
                      index,
                      action,
                    ),
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      if (index > 0)
                        const PopupMenuItem(
                          value: 'up',
                          child: Text('Move Earlier'),
                        ),
                      if (index < settings.claudeProfiles.length - 1)
                        const PopupMenuItem(
                          value: 'down',
                          child: Text('Move Later'),
                        ),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove'),
                      ),
                    ],
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add CCS Profile'),
                onTap: () async {
                  final profile = await showDialog<ClaudeQuotaProfile>(
                    context: context,
                    builder: (_) => ClaudeQuotaProfileDialog(
                      profiles: settings.claudeProfiles,
                    ),
                  );
                  if (profile != null) {
                    await controller.updateQuotas(
                      settings.copyWith(
                        claudeProfiles: <ClaudeQuotaProfile>[
                          ...settings.claudeProfiles,
                          profile,
                        ],
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        _SectionTitle(
          title: 'Credential Environment',
          description: 'Only variable names and availability leave the host.',
        ),
        Card(
          child: Column(
            children: <Widget>[
              _EnvironmentTile(
                label: 'Kimi API Key Variable',
                value: settings.environment.kimiApiKey,
                available: environmentPresence[settings.environment.kimiApiKey],
                onChanged: (value) => controller.updateQuotas(
                  settings.copyWith(
                    environment: settings.environment.copyWith(
                      kimiApiKey: value,
                    ),
                  ),
                ),
              ),
              _EnvironmentTile(
                label: 'Z.ai API Key Variable',
                value: settings.environment.zaiApiKey,
                available: environmentPresence[settings.environment.zaiApiKey],
                onChanged: (value) => controller.updateQuotas(
                  settings.copyWith(
                    environment: settings.environment.copyWith(
                      zaiApiKey: value,
                    ),
                  ),
                ),
              ),
              _EnvironmentTile(
                label: 'Z.ai Base URL Variable',
                value: settings.environment.zaiBaseUrl,
                available: environmentPresence[settings.environment.zaiBaseUrl],
                onChanged: (value) => controller.updateQuotas(
                  settings.copyWith(
                    environment: settings.environment.copyWith(
                      zaiBaseUrl: value,
                    ),
                  ),
                ),
              ),
              _EnvironmentTile(
                label: 'MiniMax API Key Variable',
                value: settings.environment.minimaxApiKey,
                available:
                    environmentPresence[settings.environment.minimaxApiKey],
                onChanged: (value) => controller.updateQuotas(
                  settings.copyWith(
                    environment: settings.environment.copyWith(
                      minimaxApiKey: value,
                    ),
                  ),
                ),
              ),
              _EnvironmentTile(
                label: 'MiniMax API Host Variable',
                value: settings.environment.minimaxApiHost,
                available:
                    environmentPresence[settings.environment.minimaxApiHost],
                onChanged: (value) => controller.updateQuotas(
                  settings.copyWith(
                    environment: settings.environment.copyWith(
                      minimaxApiHost: value,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Check Environment'),
                onTap: ref
                    .read(agentQuotaControllerProvider(hostId).notifier)
                    .refresh,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentTile extends StatelessWidget {
  const _EnvironmentTile({
    required this.label,
    required this.value,
    required this.available,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool? available;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        available == true ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: available == true
            ? AleraTokens.success
            : AleraTokens.foregroundMuted,
      ),
      title: Text(label),
      subtitle: Text(
        value,
        style: const TextStyle(fontFamily: AleraTokens.monoFontFamily),
      ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final next = await _editText(context, label, value);
        if (next != null && next != value) onChanged(next);
      },
    );
  }
}

List<T> _move<T>(List<T> values, int index, int offset) {
  final result = values.toList();
  final item = result.removeAt(index);
  result.insert(index + offset, item);
  return result;
}

Future<void> _handleProfileAction(
  BuildContext context,
  HostSettingsController controller,
  QuotaSettings settings,
  int index,
  String action,
) async {
  final profiles = settings.claudeProfiles.toList();
  switch (action) {
    case 'up':
      await controller.updateQuotas(
        settings.copyWith(claudeProfiles: _move(profiles, index, -1)),
      );
    case 'down':
      await controller.updateQuotas(
        settings.copyWith(claudeProfiles: _move(profiles, index, 1)),
      );
    case 'remove':
      profiles.removeAt(index);
      await controller.updateQuotas(
        settings.copyWith(claudeProfiles: profiles),
      );
    case 'edit':
      final updated = await showDialog<ClaudeQuotaProfile>(
        context: context,
        builder: (_) => ClaudeQuotaProfileDialog(
          profiles: profiles,
          initial: profiles[index],
        ),
      );
      if (updated != null) {
        profiles[index] = updated;
        await controller.updateQuotas(
          settings.copyWith(claudeProfiles: profiles),
        );
      }
  }
}

Future<String?> _editText(
  BuildContext context,
  String label,
  String value,
) async {
  final controller = TextEditingController(text: value);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Variable Name'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result?.isEmpty == true ? null : result;
}
