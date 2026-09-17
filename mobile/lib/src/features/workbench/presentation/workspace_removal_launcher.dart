import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/delete_workspace_dialog.dart';
import 'package:flutter/material.dart';

/// Confirms and removes [workspace] using the same dialog as the workspace
/// actions sheet. Returns true when the workspace was removed.
Future<bool> confirmAndDeleteWorkspace(
  BuildContext context,
  WorkspaceListController controller,
  WorkspaceSummary workspace,
  WorkspaceListData data,
) async {
  var cascadeCount = 1;
  try {
    cascadeCount = (await controller.cascadePreview(workspace.id)).length;
  } on Object {
    // The preview is advisory; deletion still confirms explicitly.
  }
  if (!context.mounted) {
    return false;
  }
  final dependencies = await controller.removalDependencies(workspace.id);
  if (!context.mounted) {
    return false;
  }
  final decision = data.confirmWorkspaceRemoval || dependencies.isNotEmpty
      ? await showDeleteWorkspaceDialog(
          context,
          workspace: workspace,
          cascadeCount: cascadeCount,
          dependencies: dependencies,
        )
      : DeleteWorkspaceDecision(
          deleteBranch: !workspace.isMain && !workspace.reusesExistingBranch,
        );
  if (decision == null || !context.mounted) {
    return false;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text('Removing ${workspace.name}')));
  if (decision.pauseAutomations) {
    await controller.pauseRemovalDependencies(workspace.id, dependencies);
  }
  await controller.deleteWorkspace(
    workspace.id,
    deleteBranch: decision.deleteBranch,
  );
  messenger.showSnackBar(SnackBar(content: Text('Removed ${workspace.name}')));
  return true;
}
