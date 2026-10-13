import 'dart:async';

import 'package:alera/src/app/app_navigation.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_job_card.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [host] gets a job card: an install running, or one that failed and
/// was not dismissed, while no install dialog is showing it.
bool remoteHostShowsInstallCard(RemoteHostsState state, RemoteHostView host) {
  final install = host.installProgress;
  if (install == null || state.isInstallDialogOpen(host.id)) {
    return false;
  }
  return install.isRunning || install.failed;
}

/// Whether any host currently has an install job card.
bool remoteHostsHaveInstallCards(RemoteHostsState state) =>
    state.hosts.any((host) => remoteHostShowsInstallCard(state, host));

/// Job cards for Alera runtime installs the user is not watching in a dialog.
class const RemoteHostInstallJobCards({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(remoteHostsControllerProvider);
    final hosts = <RemoteHostView>[
      for (final host in state.hosts)
        if (remoteHostShowsInstallCard(state, host)) host,
    ];
    if (hosts.isEmpty) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(remoteHostsControllerProvider.notifier);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .end,
      children: <Widget>[
        for (final host in hosts) ...<Widget>[
          _InstallCard(
            host: host,
            onCancel: () => unawaited(controller.cancelInstall(host.id)),
            onRetry: () {
              final context = aleraNavigatorKey.currentContext;
              if (context != null) {
                unawaited(openRemoteHostSettings(context, hostId: host.id));
              }
            },
            onDismiss: () => controller.dismissInstallFailure(host.id),
          ),
          const SizedBox(height: AleraTokens.space8),
        ],
      ],
    );
  }
}

class const _InstallCard({
  required final RemoteHostView host,
  required final VoidCallback onCancel,
  required final VoidCallback onRetry,
  required final VoidCallback onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final install = host.installProgress!;
    final updating = install.includesRestart;
    if (install.failed) {
      return AleraJobCard(
        title: updating
            ? 'Could not update the Alera runtime on ${host.alias}'
            : 'Could not install the Alera runtime on ${host.alias}',
        status: .failed,
        error: install.error ?? 'The Alera runtime install failed.',
        onRetry: onRetry,
        onDismiss: onDismiss,
      );
    }
    return AleraJobCard(
      title: updating
          ? 'Updating Alera runtime on ${host.alias}'
          : 'Installing Alera runtime on ${host.alias}',
      status: .running,
      phase: install.phaseLabel,
      progress: install.fraction,
      onCancel: host.busy ? null : onCancel,
    );
  }
}
