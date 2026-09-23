import 'package:alera/src/app/providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/workspace.dart';
import '../infra/workspace_relocation_recovery_client.dart';
import 'workspace_relocation_recovery_dialog.dart';

Future<void> showWorkspaceRecoveryFlow(
  BuildContext context,
  Workspace workspace,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  final client = WorkspaceRelocationRecoveryClient(
    container.read(runtimeHostClientProvider),
    beforeAccess: container.read(runtimeStateMigrationProvider).ensureMigrated,
  );
  return showWorkspaceRelocationRecoveryDialog(
    context: context,
    load: () => client.inspect(workspace),
    onResume: (entry) => container
        .read(workbenchControllerProvider.notifier)
        .resumeWorkspaceRelocation(workspace, entry),
    onRunSetup: (entry) => client.runSetup(workspace, entry),
    onCancelSetup: (entry) => client.cancelSetup(workspace, entry),
    onRecoverSetup: (entry) => client.recoverSetup(workspace, entry),
  );
}
