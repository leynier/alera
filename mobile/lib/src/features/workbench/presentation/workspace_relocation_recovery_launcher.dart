import 'package:alera_mobile/src/features/runtime/domain/workspace_recovery_client.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/deferred_workspace_setup_launcher.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workspace_relocation_recovery_dialog.dart';

Future<void> showWorkspaceRecoveryFlow(
  BuildContext context, {
  required String hostId,
  required WorkspaceSummary workspace,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  Future<WorkspaceRecoveryClient> client() async {
    final connected = await container.read(
      workspaceClientProvider(hostId).future,
    );
    if (connected is! WorkspaceRecoveryClient ||
        !(connected as WorkspaceRecoveryClient).supportsWorkspaceRecovery) {
      throw UnsupportedError(
        'Update Alera on this host to use workspace recovery.',
      );
    }
    return connected as WorkspaceRecoveryClient;
  }

  return showWorkspaceRelocationRecoveryDialog(
    context: context,
    load: () async => (await client()).inspectWorkspaceRecovery(workspace),
    onResume: (entry) async {
      try {
        final result = await (await client()).resumeWorkspaceRecovery(
          workspace,
          entry,
          sharedImpactConfirmed: true,
        );
        if (result.hasDeferredSetup) {
          final terminal = await container.read(
            terminalClientProvider(hostId).future,
          );
          final launched = await launchDeferredWorkspaceSetup(terminal, result);
          if (launched.setupLaunchError != null) {
            throw StateError(
              'The transfer completed, but setup could not be opened: ${launched.setupLaunchError}',
            );
          }
        }
      } finally {
        container.invalidate(workspaceListControllerProvider(hostId));
      }
    },
    onRunSetup: (entry) async =>
        (await client()).runWorkspaceRecoverySetup(workspace, entry),
    onCancelSetup: (entry) async =>
        (await client()).cancelWorkspaceRecoverySetup(workspace, entry),
    onRecoverSetup: (entry) async =>
        (await client()).recoverWorkspaceSetupOutcome(workspace, entry),
  );
}
