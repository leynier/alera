import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_action_result.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `Close 2 Terminals and Update`, the confirm label for a busy host.
String closeTerminalsAndUpdateLabel(int count) => count == 1
    ? 'Close 1 Terminal and Update'
    : 'Close $count Terminals and Update';

/// Update Runtime for [hostId]. Restarting the runtime closes the terminals
/// open there, so a busy host asks first and then retries with force.
Future<RemoteHostActionResult> updateRemoteHostRuntime(
  BuildContext context,
  WidgetRef ref,
  String hostId,
) async {
  final controller = ref.read(remoteHostsControllerProvider.notifier);
  final result = await controller.updateRuntime(hostId);
  final busy = result.hostBusy;
  if (busy == null || !context.mounted) {
    return result;
  }
  controller.clearError(hostId);
  final count = busy.activeSessions;
  final name = busy.alias.isEmpty ? 'this host' : busy.alias;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: 'Close Terminals?',
      message: count == 1
          ? 'Updating restarts the Alera runtime on $name, which closes the terminal open there and stops any agent running in it.'
          : 'Updating restarts the Alera runtime on $name, which closes the $count terminals open there and stops any agents running in them.',
      confirmLabel: closeTerminalsAndUpdateLabel(count),
      destructive: true,
    ),
  );
  if (confirmed != true) {
    return result;
  }
  return controller.updateRuntime(hostId, force: true);
}
