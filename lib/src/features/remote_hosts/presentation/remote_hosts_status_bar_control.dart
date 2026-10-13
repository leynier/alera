import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_action_result.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_runtime_update_flow.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_hosts_status_panel.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status bar control for remote hosts. Absent until a host is registered.
class const RemoteHostsStatusBarControl({super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<RemoteHostsStatusBarControl> createState() =>
      _RemoteHostsStatusBarControlState();
}

class _RemoteHostsStatusBarControlState
    extends ConsumerState<RemoteHostsStatusBarControl> {
  final AleraHoverCardController _hoverCard = AleraHoverCardController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remoteHostsControllerProvider);
    if (state.hosts.isEmpty) {
      return const SizedBox.shrink();
    }
    return AleraHoverCard(
      controller: _hoverCard,
      // The chip runs its own InkWell, so it drives pinning itself.
      pinOnTap: false,
      semanticsLabel: 'Remote Hosts',
      card: RemoteHostsStatusPanel(
        hosts: state.hosts,
        capabilities: state.capabilities,
        onQuickAction: (host, action) => unawaited(_run(host, action)),
        onOpenHost: (hostId) =>
            _navigate(() => openRemoteHostSettings(context, hostId: hostId)),
        onOpenRemoteHosts: () =>
            _navigate(() => openRemoteHostSettings(context)),
        onAddHost: () => _navigate(() => showAddRemoteHostFlow(context, ref)),
      ),
      child: RemoteHostsStatusChip(
        hosts: state.hosts,
        onPressed: _hoverCard.togglePin,
      ),
    );
  }

  void _navigate(Future<Object?> Function() open) {
    _hoverCard.dismiss();
    unawaited(open());
  }

  Future<void> _run(RemoteHostView host, RemoteHostQuickAction action) async {
    final controller = ref.read(remoteHostsControllerProvider.notifier);
    final RemoteHostActionResult result;
    switch (action) {
      case RemoteHostQuickAction.connect:
        result = await controller.connect(host.id);
      case RemoteHostQuickAction.retry:
        final installFailed = switch (host.status) {
          RemoteHostError(:final origin) =>
            origin == RemoteHostErrorOrigin.install,
          _ => false,
        };
        result = installFailed
            ? await controller.install(host.id)
            : await controller.connect(host.id);
      case RemoteHostQuickAction.update:
        result = await updateRemoteHostRuntime(context, ref, host.id);
    }
    // A busy host the user chose not to interrupt is not a failure.
    if (result.hostBusy != null) {
      return;
    }
    if (result.errorMessage case final message? when mounted) {
      AleraToast.show(
        context,
        message: message,
        tone: .error,
        duration: AleraToast.longDuration,
      );
    }
  }
}
