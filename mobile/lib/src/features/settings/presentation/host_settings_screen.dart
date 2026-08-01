import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/projects/presentation/projects_screen.dart';
import 'package:alera_mobile/src/features/projects/presentation/remote_directory_picker_screen.dart';
import 'package:alera_mobile/src/features/quotas/presentation/agent_quotas_screen.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_restart_result.dart';
import 'package:alera_mobile/src/features/settings/application/host_settings_controller.dart';
import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:alera_mobile/src/features/settings/presentation/host_agent_tools_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HostSettingsScreen extends ConsumerWidget {
  const HostSettingsScreen({super.key, required this.host});

  final PairedHostProfile host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(hostSettingsControllerProvider(host.id));
    final settingsValue = settings.value;
    ref.listen(hostSettingsControllerProvider(host.id), (previous, next) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error.toString())));
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Host Settings')),
      body: SafeArea(
        child: settingsValue != null
            ? _SettingsBody(host: host, settings: settingsValue)
            : settings.hasError
            ? _UnsupportedSettings(error: settings.error!)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.host, required this.settings});

  final PairedHostProfile host;
  final PortableHostSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      hostSettingsControllerProvider(host.id).notifier,
    );
    final connection = ref.watch(hostConnectionControllerProvider(host.id));
    final supportsRuntimeRestart =
        connection.value?.supportsRuntimeRestart == true;
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        const _ScopeBanner(),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('General', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Workspace Directory'),
                subtitle: Text(
                  settings.workspaceDirectory ?? 'Host default',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AleraTokens.monoFontFamily,
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'reset') {
                      await controller.updateWorkspaceDirectory(null);
                      return;
                    }
                    final path = await Navigator.of(context).push<String>(
                      MaterialPageRoute<String>(
                        builder: (_) => RemoteDirectoryPickerScreen(
                          hostId: host.id,
                          actionLabel: 'Use This Folder',
                        ),
                      ),
                    );
                    if (path != null) {
                      await controller.updateWorkspaceDirectory(path);
                    }
                  },
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'choose',
                      child: Text('Choose Folder'),
                    ),
                    PopupMenuItem(
                      value: 'reset',
                      child: Text('Use Host Default'),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                value: settings.confirmProjectRemoval,
                onChanged: controller.setConfirmProjectRemoval,
                title: const Text('Confirm Project Removal'),
                subtitle: const Text('Ask before removing project metadata.'),
              ),
              SwitchListTile(
                value: settings.confirmWorkspaceRemoval,
                onChanged: controller.setConfirmWorkspaceRemoval,
                title: const Text('Confirm Workspace Removal'),
                subtitle: const Text(
                  'Ask before removing a managed workspace.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        if (supportsRuntimeRestart) ...<Widget>[
          Text('Runtime', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AleraTokens.spaceSm),
          Card(
            child: ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Restart Runtime'),
              subtitle: const Text(
                'Restart the runtime host and reconnect this app.',
              ),
              onTap: () => _restartRuntime(context, ref, host.id),
            ),
          ),
          const SizedBox(height: AleraTokens.spaceXl),
        ],
        Text('Manage', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Column(
            children: <Widget>[
              _NavigationTile(
                icon: Icons.account_tree_outlined,
                title: 'Projects',
                scope: 'On this host',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ProjectsScreen(host: host),
                  ),
                ),
              ),
              _NavigationTile(
                icon: Icons.speed_outlined,
                title: 'Quotas',
                scope: 'On this host',
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AgentQuotasScreen(host: host),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.spaceXl),
        HostAgentToolsSection(hostId: host.id),
        const SizedBox(height: AleraTokens.spaceXl),
        Text('Status Hooks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AleraTokens.spaceSm),
        Card(
          child: Column(
            children: <Widget>[
              for (final agent in supportedAgentHooks)
                SwitchListTile(
                  value: settings.agentStatusHooks[agent] == true,
                  onChanged: (value) => controller.setAgentHook(agent, value),
                  title: Text('${agentHookLabels[agent]} Hooks'),
                  subtitle: const Text('Report direct terminal agent status.'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _restartRuntime(
  BuildContext context,
  WidgetRef ref,
  String hostId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const AleraConfirmDialog(
      title: 'Restart Runtime?',
      message:
          'Restarting disconnects every client. Active terminals, agents, emulators, and background jobs must stop first.',
      confirmLabel: 'Restart Runtime',
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }

  final controller = ref.read(
    hostConnectionControllerProvider(hostId).notifier,
  );
  try {
    await controller.restartRuntime();
  } on RuntimeRestartBusyException catch (busy) {
    if (!context.mounted) {
      return;
    }
    final force = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Force Restart Runtime?',
        message: busy.confirmationMessage,
        confirmLabel: 'Force Restart',
        destructive: true,
      ),
    );
    if (force != true) {
      return;
    }
    try {
      await controller.restartRuntime(force: true);
    } on Object {
      if (context.mounted) {
        _showRestartFailure(context);
      }
      return;
    }
  } on Object {
    if (context.mounted) {
      _showRestartFailure(context);
    }
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Runtime restarting')));
  }
}

void _showRestartFailure(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Could not restart runtime')));
}

class _ScopeBanner extends StatelessWidget {
  const _ScopeBanner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
      ),
      child: const Padding(
        padding: AleraTokens.contentPadding,
        child: Row(
          children: <Widget>[
            Icon(Icons.sync_outlined, color: AleraTokens.info),
            SizedBox(width: AleraTokens.spaceMd),
            Expanded(
              child: Text(
                'Host settings sync live with every connected Alera client.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.icon,
    required this.title,
    required this.scope,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String scope;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(scope),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _UnsupportedSettings extends StatelessWidget {
  const _UnsupportedSettings({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Text(error.toString(), textAlign: TextAlign.center),
      ),
    );
  }
}
