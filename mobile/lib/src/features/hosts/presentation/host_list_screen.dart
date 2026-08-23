import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/presentation/pair_host_screen.dart';
import 'package:alera_mobile/src/features/hosts/presentation/rename_host_dialog.dart';
import 'package:alera_mobile/src/features/quotas/presentation/home_quotas_section.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/settings/presentation/app_settings_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/runtime_workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HostListScreen extends ConsumerWidget {
  const HostListScreen({super.key});

  Future<void> _pairHost(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const PairHostScreen()),
    );
  }

  Future<void> _removeHost(
    BuildContext context,
    WidgetRef ref,
    PairedHostProfile host,
  ) async {
    if (host.isRemote) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Host'),
        content: Text(host.displayName),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(pairedHostsControllerProvider.notifier).removeHost(host.id);
  }

  Future<void> _showHostActions(
    BuildContext context,
    WidgetRef ref,
    PairedHostProfile host,
  ) async {
    if (host.isRemote) {
      return;
    }
    final action = await showModalBottomSheet<_HostAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename Host'),
              onTap: () => Navigator.of(context).pop(_HostAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove Host'),
              onTap: () => Navigator.of(context).pop(_HostAction.remove),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) {
      return;
    }
    switch (action) {
      case _HostAction.rename:
        await showRenameHostDialog(context, ref, host);
      case _HostAction.remove:
        await _removeHost(context, ref, host);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(availableHostsProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: const Padding(
          padding: EdgeInsets.all(AleraTokens.space12),
          child: Image(
            image: AssetImage('assets/branding/alera-logo-white.png'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        title: const Text('Alera'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AppSettingsScreen(),
                ),
              );
            },
            icon: const Icon(AleraIcons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (hosts) {
          AsyncData(value: final hostList) when hostList.isEmpty => _EmptyHosts(
            onPairHost: () => _pairHost(context),
          ),
          AsyncData(value: final hostList) => ListView(
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space16,
              AleraTokens.space4,
              AleraTokens.space16,
              AleraTokens.space16,
            ),
            children: <Widget>[
              const AleraSectionHeader(
                label: 'Hosts',
                padding: EdgeInsets.only(
                  left: AleraTokens.space4,
                  right: AleraTokens.space8,
                  bottom: AleraTokens.space4,
                ),
              ),
              for (var index = 0; index < hostList.length; index++) ...<Widget>[
                _HostCard(
                  host: hostList[index],
                  onOpen: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RuntimeWorkspacesScreen(host: hostList[index]),
                      ),
                    );
                  },
                  onRemove: () => _removeHost(context, ref, hostList[index]),
                  onLongPress: () =>
                      _showHostActions(context, ref, hostList[index]),
                ),
                if (index < hostList.length - 1)
                  const SizedBox(height: AleraTokens.spaceMd),
              ],
              HomeQuotasSection(hosts: hostList),
            ],
          ),
          AsyncError(:final error) => Center(child: Text(error.toString())),
          _ => const _HomeLoading(),
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Pair Host',
        onPressed: () => _pairHost(context),
        child: const Icon(Icons.add_link),
      ),
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AleraTokens.spaceMd),
          Text('Loading Alera', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _EmptyHosts extends StatelessWidget {
  const _EmptyHosts({required this.onPairHost});

  final VoidCallback onPairHost;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.devices_other,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'No paired hosts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            FilledButton.icon(
              onPressed: onPairHost,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Pair Host'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _HostAction { rename, remove }

class _HostCard extends ConsumerWidget {
  const _HostCard({
    required this.host,
    required this.onOpen,
    required this.onRemove,
    required this.onLongPress,
  });

  final PairedHostProfile host;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(hostConnectionControllerProvider(host.id));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        onTap: onOpen,
        onLongPress: onLongPress,
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Row(
            children: <Widget>[
              Container(
                width: AleraTokens.iconLg,
                height: AleraTokens.iconLg,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(
                    alpha: AleraTokens.emphasisOverlayAlpha,
                  ),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                ),
                child: Icon(
                  Icons.computer,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: AleraTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      host.effectiveName,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (host.alias != null) ...<Widget>[
                      const SizedBox(height: AleraTokens.spaceXs),
                      Text(
                        host.displayName,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AleraTokens.spaceXs),
                    Text(
                      host.endpoint,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AleraTokens.spaceSm),
                    _HostConnectionStatus(
                      connecting: connection.isLoading,
                      ready: connection.hasValue && !connection.hasError,
                      onRetry: () => unawaited(
                        ref
                            .read(
                              hostConnectionControllerProvider(
                                host.id,
                              ).notifier,
                            )
                            .reconnectNow(),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove Host',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostConnectionStatus extends StatelessWidget {
  const _HostConnectionStatus({
    required this.connecting,
    required this.ready,
    required this.onRetry,
  });

  final bool connecting;
  final bool ready;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final label = connecting
        ? 'Connecting'
        : ready
        ? 'Ready'
        : 'Unavailable';
    return Row(
      children: <Widget>[
        if (connecting)
          const SizedBox.square(
            dimension: AleraTokens.spaceMd,
            child: CircularProgressIndicator(strokeWidth: AleraTokens.strokeSm),
          )
        else
          AleraStatusDot(
            active: ready,
            size: AleraTokens.spaceSm,
            color: ready ? null : AleraTokens.error,
          ),
        const SizedBox(width: AleraTokens.spaceSm),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        if (!connecting && !ready) ...<Widget>[
          const SizedBox(width: AleraTokens.spaceSm),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    );
  }
}
