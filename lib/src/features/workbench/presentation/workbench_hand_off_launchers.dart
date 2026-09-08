import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_hand_off_dialog.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showHandOffWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  required Workspace workspace,
}) async {
  if (!workspace.isMain) {
    return;
  }
  String currentBranch;
  try {
    currentBranch = await ref
        .read(gitBackendProvider)
        .currentBranch(workspace.path);
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(context, message: error.toString(), tone: .error);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  final request = await showWorkspaceHandOffDialog(
    context: context,
    currentBranch: currentBranch,
  );
  if (request == null || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(workbenchControllerProvider.notifier)
        .handOffWorkspace(
          workspace: workspace,
          branch: request.branch,
          reuseExistingBranch: request.reuseExistingBranch,
          name: request.name,
        );
    if (!context.mounted) {
      return;
    }
    AleraToast.show(context, message: 'Work handed off', tone: .success);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(context, message: error.toString(), tone: .error);
  }
}

Future<void> showHandOnWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  required Project project,
  required Workspace workspace,
}) async {
  if (workspace.isMain) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: 'Hand On to Main?',
      message:
          'This brings the branch and uncommitted changes from "${workspace.name}" onto the main worktree, then removes this child workspace. Running terminals in the child workspace will stop.',
      confirmLabel: 'Hand On',
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(workbenchControllerProvider.notifier)
        .handOnWorkspace(project: project, workspace: workspace);
    if (!context.mounted) {
      return;
    }
    AleraToast.show(context, message: 'Work handed on to main', tone: .success);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(context, message: error.toString(), tone: .error);
  }
}
