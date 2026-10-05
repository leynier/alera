import 'dart:async';

import 'package:alera_mobile/src/features/runtime/application/host_connection_health.dart';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/presentation/pair_host_screen.dart';
import 'package:alera_mobile/src/features/hosts/presentation/rename_host_dialog.dart';
import 'package:alera_mobile/src/features/quotas/presentation/home_quotas_section.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/settings/presentation/app_settings_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/runtime_workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

class const HostListScreen({super.key}) extends ConsumerWidget {
  static final Logger _logger = Logger('HostListScreen');

  Future<void> _pairHost(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const PairHostScreen()),
    );
  }

  Future<void> _refreshHosts(WidgetRef ref) async {
    ref.invalidate(availableHostsProvider);
    try {
      await ref.read(availableHostsProvider.future);
    } on Object catch (error, stackTrace) {
      // The list renders the failure; this keeps a record of it.
      _logger.warning('Could not refresh paired hosts.', error, stackTrace);
    }
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
      builder: (context) => AleraConfirmDialog(
        title: 'Remove ${host.effectiveName}?',
        message:
            'This phone forgets the pairing and stops connecting to this '
            'host. To connect again, pair it with a new QR code from the '
            'computer.',
        confirmLabel: 'Remove',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    unawaited(HapticFeedback.lightImpact());
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
    final action = await showAleraActionSheet<_HostAction>(
      context,
      entries: const <AleraActionSheetEntry<_HostAction>>[
        AleraActionSheetEntry<_HostAction>(
          value: _HostAction.rename,
          label: 'Rename Host',
          leading: Icon(AleraIcons.edit),
        ),
        AleraActionSheetEntry<_HostAction>(
          value: _HostAction.remove,
          label: 'Remove Host',
          leading: Icon(AleraIcons.delete),
          destructive: true,
        ),
      ],
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
            fit: .contain,
            filterQuality: .medium,
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
        child: RefreshIndicator(
          onRefresh: () => _refreshHosts(ref),
          child: switch (hosts) {
            AsyncValue(value: final hostList?) when hostList.isEmpty =>
              _FillRemaining(
                child: AleraEmptyState(
                  icon: AleraIcons.pairedDevices,
                  title: 'No paired hosts',
                  message:
                      'Open Alera on your computer, go to Settings > Mobile '
                      'Devices, generate a pairing QR code, and scan it with '
                      'this phone.',
                  action: FilledButton.icon(
                    onPressed: () => _pairHost(context),
                    icon: const Icon(AleraIcons.qrCode),
                    label: const Text('Pair Host'),
                  ),
                ),
              ),
            AsyncValue(value: final hostList?) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                for (
                  var index = 0;
                  index < hostList.length;
                  index++
                ) ...<Widget>[
                  _HostCard(
                    key: ValueKey(hostList[index].id),
                    host: hostList[index],
                    onOpen: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RuntimeWorkspacesScreen(host: hostList[index]),
                        ),
                      );
                    },
                    onActions: hostList[index].isRemote
                        ? null
                        : () => _showHostActions(context, ref, hostList[index]),
                  ),
                  if (index < hostList.length - 1)
                    const SizedBox(height: AleraTokens.spaceMd),
                ],
                HomeQuotasSection(hosts: hostList),
              ],
            ),
            AsyncError(:final error) => _FillRemaining(
              child: AleraEmptyState(
                icon: AleraIcons.loadFailed,
                title: 'Could not load hosts',
                message: 'Pull down or tap Retry to try again.',
                detail: error.toString(),
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(availableHostsProvider),
                  icon: const Icon(AleraIcons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ),
            _ => const _HomeLoading(),
          },
        ),
      ),
      // The empty state already offers Pair Host; a FAB there would repeat it.
      floatingActionButton: hosts.value?.isNotEmpty == true
          ? FloatingActionButton(
              tooltip: 'Pair Host',
              onPressed: () => _pairHost(context),
              child: const Icon(Icons.add_link),
            )
          : null,
    );
  }
}

/// Lets a short placeholder fill the screen while staying scrollable, so
/// pull-to-refresh still works on an empty or failed list.
class const _FillRemaining({required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }
}

class const _HomeLoading() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AleraTokens.spaceMd),
          Text('Loading Alera', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

enum _HostAction { rename, remove }

class const _HostCard({
  super.key,
  required final PairedHostProfile host,
  required final VoidCallback onOpen,
  required final VoidCallback? onActions,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(hostConnectionControllerProvider(host.id));
    final health = ref.watch(hostConnectionHealthControllerProvider(host.id));
    return Card(
      child: InkWell(
        onTap: onOpen,
        onLongPress: onActions,
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Row(
            children: <Widget>[
              Container(
                width: AleraTokens.iconLg,
                height: AleraTokens.iconLg,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: AleraTokens.emphasisOverlayAlpha),
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
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      host.effectiveName,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: .ellipsis,
                    ),
                    if (host.alias != null) ...<Widget>[
                      const SizedBox(height: AleraTokens.spaceXs),
                      Text(
                        host.displayName,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: .ellipsis,
                      ),
                    ],
                    const SizedBox(height: AleraTokens.spaceXs),
                    Text(
                      host.endpoint,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: .ellipsis,
                    ),
                    const SizedBox(height: AleraTokens.spaceSm),
                    if (host.discoveryStale)
                      Text(
                        'Discovery unavailable. Showing the last known host.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    _HostConnectionStatus(
                      health: health,
                      connecting: connection.isLoading,
                      ready: connection.hasValue && !connection.hasError,
                      onRetry: () => unawaited(
                        ref
                            .read(
                              hostConnectionControllerProvider(host.id)
                                  .notifier,
                            )
                            .reconnectNow(),
                      ),
                    ),
                  ],
                ),
              ),
              if (onActions case final onActions?)
                IconButton(
                  tooltip: 'More Actions',
                  onPressed: onActions,
                  icon: const Icon(AleraIcons.more),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _HostConnectionStatus({
  required final bool connecting,
  required final bool ready,
  required final VoidCallback onRetry,
  required final HostConnectionHealth health,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final label = health.phase == 'blocked'
        ? 'Sign-in or connection review required'
        : connecting
        ? 'Connecting'
        : ready
        ? 'Ready${health.transport == null ? '' : ' via ${health.transport}'}'
        : health.nextRetryAt != null
        ? 'Retrying at ${TimeOfDay.fromDateTime(health.nextRetryAt!.toLocal()).format(context)}'
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
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
        if (!connecting && !ready) ...<Widget>[
          const SizedBox(width: AleraTokens.spaceSm),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    );
  }
}
