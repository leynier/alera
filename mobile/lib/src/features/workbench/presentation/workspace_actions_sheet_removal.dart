part of 'workspace_actions_sheet.dart';

Future<void> _confirmAndDelete(
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
    return;
  }
  final dependencies = await controller.removalDependencies(workspace.id);
  if (!context.mounted) return;
  final branch = workspace.branch?.trim();
  final canDeleteBranch =
      !workspace.isMain &&
      !workspace.reusesExistingBranch &&
      branch != null &&
      branch.isNotEmpty;
  final decision = data.confirmWorkspaceRemoval || dependencies.isNotEmpty
      ? await showWorkspaceRemovalDialog(
          context,
          workspace: workspace,
          cascadeCount: cascadeCount,
          dependencies: dependencies,
        )
      : WorkspaceRemovalDecision(deleteBranch: canDeleteBranch);
  if (decision == null || !context.mounted) {
    return;
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
}
