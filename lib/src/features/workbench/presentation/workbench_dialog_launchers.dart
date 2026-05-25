import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:alera/src/features/settings/presentation/settings_dialog.dart';
import 'package:alera/src/features/workbench/presentation/create_workspace_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared dialog flows for project/workspace creation and settings.
///
/// Extracted so both the sidebar controls and the keyboard command dispatcher
/// trigger the exact same behavior (dialogs, clone progress, toasts).

Future<void> openSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const SettingsDialog(),
  );
}

/// Opens the add-project dialog and runs the chosen local-folder or clone flow.
Future<void> showAddProjectFlow(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<AddProjectResult>(
    context: context,
    builder: (_) => const AddProjectDialog(),
  );
  if (result == null || !context.mounted) {
    return;
  }
  final controller = ref.read(workbenchControllerProvider.notifier);
  try {
    switch (result) {
      case AddLocalProjectResult():
        await controller.addLocalProject(path: result.path, name: result.name);
        if (!context.mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Project added',
          tone: AleraToastTone.success,
        );
      case CloneProjectResult():
        await _runWithProgress(
          context,
          message: 'Cloning repository…',
          action: () => controller.cloneProject(
            gitUrl: result.gitUrl,
            destinationPath: result.destinationPath,
            name: result.name,
          ),
        );
        if (!context.mounted) {
          return;
        }
        AleraToast.show(
          context,
          message: 'Project cloned',
          tone: AleraToastTone.success,
        );
    }
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: error.toString(),
      tone: AleraToastTone.error,
    );
  }
}

/// Opens the create-workspace dialog for the active Git project. Linked
/// workspaces require a Git project, so folder-only projects are filtered out.
Future<void> showCreateWorkspaceFlow(
  BuildContext context,
  WidgetRef ref, {
  Project? initialProject,
}) async {
  final controller = ref.read(workbenchControllerProvider.notifier);
  final projects = ref
      .read(workbenchControllerProvider)
      .projects
      .where((project) => project.supportsLinkedWorkspaces)
      .toList(growable: false);
  if (projects.isEmpty) {
    AleraToast.show(
      context,
      message: 'Linked workspaces require a Git project.',
      tone: AleraToastTone.info,
    );
    return;
  }
  final resolvedInitialProject =
      initialProject?.supportsLinkedWorkspaces == true ? initialProject : null;

  final result = await showDialog<CreateWorkspaceResult>(
    context: context,
    builder: (_) => CreateWorkspaceDialog(
      projects: projects,
      initialProject: resolvedInitialProject,
      loadBranches: controller.listSourceBranches,
    ),
  );
  if (result == null || !context.mounted) {
    return;
  }
  try {
    await controller.createWorkspace(
      project: result.project,
      sourceBranch: result.sourceBranch,
      newBranchName: result.newBranchName,
      name: result.name,
    );
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Workspace created',
      tone: AleraToastTone.success,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: error.toString(),
      tone: AleraToastTone.error,
    );
  }
}

Future<T> _runWithProgress<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() action,
}) async {
  var progressOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddProjectProgressDialog(message: message),
    ).whenComplete(() => progressOpen = false),
  );
  await Future<void>.delayed(Duration.zero);
  try {
    return await action();
  } finally {
    if (context.mounted && progressOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
