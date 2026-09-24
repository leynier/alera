import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_value_format.dart';
import 'package:alera/src/features/workbench/application/workspace_removal_dependencies.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_storage_impact.dart';
import 'package:alera/src/features/workbench/presentation/workspace_removal_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs the same confirmed workspace removal flow as the sidebar Remove action.
Future<void> showWorkspaceRemovalFlow({
  required BuildContext context,
  required WidgetRef ref,
  required Project project,
  required Workspace workspace,
}) async {
  final branch = workspace.branch;
  final canDeleteBranch =
      !workspace.isMain &&
      !workspace.reusesExistingBranch &&
      branch != null &&
      branch.isNotEmpty;

  final managedRuntime = ref.read(managedWorkspaceRuntimeProvider);
  final WorkspaceRemovalDependencyRuntime? dependencyRuntime =
      managedRuntime is WorkspaceRemovalDependencyRuntime
      ? managedRuntime as WorkspaceRemovalDependencyRuntime
      : null;
  List<WorkspaceRemovalDependency> dependencies;
  try {
    dependencies =
        await dependencyRuntime?.removalDependencies(workspace.id) ?? const [];
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(
        context,
        message: 'Could not verify automation dependencies: $error',
        tone: .error,
      );
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  WorkspaceStorageImpact? impact;
  if (!workspace.isMain && managedRuntime is WorkspaceStorageRuntime) {
    try {
      final measuredImpact = await (managedRuntime as WorkspaceStorageRuntime)
          .storageImpact(
            workspaceId: workspace.id,
            activeWorkspaceId: ref
                .read(workbenchControllerProvider)
                .activeWorkspaceId,
          );
      impact = measuredImpact;
      if (!context.mounted) {
        return;
      }
      final blockers = measuredImpact.blockers
          .where(
            (blocker) =>
                !(blocker == 'Workspace is owned by an active automation' &&
                    dependencies.any((dependency) => dependency.requiresPause)),
          )
          .toList();
      if (!measuredImpact.safeToClean && blockers.isNotEmpty) {
        await showDialog<bool>(
          context: context,
          builder: (_) => AleraConfirmDialog(
            title: 'Cleanup Unavailable',
            message:
                'Alera measured ${formatResourceMemory(measuredImpact.sizeBytes)} across '
                '${measuredImpact.entryCount} entries. Cleanup is blocked:\n\n'
                '${blockers.map((blocker) => '• $blocker').join('\n')}',
            confirmLabel: 'Close',
            cancelLabel: 'Cancel',
          ),
        );
        return;
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Could not inspect workspace storage: $error',
        tone: .error,
      );
      return;
    }
  }
  final lastActivity =
      ref.read(workspaceActivityControllerProvider)[workspace.id] ??
      impact?.lastActivityAt ??
      workspace.updatedAt;
  final impactSummary = impact == null
      ? ''
      : 'Measured size: ${formatResourceMemory(impact.sizeBytes)} '
            'across ${impact.entryCount} entries.\n'
            'Last activity: ${_workspaceStorageTimestamp(lastActivity)}.\n\n';
  final decision = await showWorkspaceRemovalDialog(
    context,
    workspaceName: workspace.name,
    branch: branch,
    canDeleteBranch: canDeleteBranch,
    sharedCheckout: workspace.isMain,
    impactSummary: impactSummary,
  );
  if (decision == null || !context.mounted) {
    return;
  }
  final registry = ref.read(editorSessionRegistryProvider);
  final tabsToDiscard = <String>[];
  final dirtyTabs = ref
      .read(workbenchControllerProvider)
      .tabsFor(workspace.id)
      .where((tab) => registry.isDirty(tab.id))
      .toList();
  if (dirtyTabs.isNotEmpty) {
    final save = await showWorkspaceUnsavedChangesDialog(
      context,
      dirtyTabs.map((tab) => tab.title).toList(),
    );
    if (save == null || !context.mounted) {
      return;
    }
    if (save) {
      try {
        final files = ref.read(workspaceFileServiceProvider);
        for (final tab in dirtyTabs) {
          await registry.saveDocument(tab.id, files);
        }
        if (dirtyTabs.any((tab) => registry.isDirty(tab.id))) {
          throw StateError('Some documents still have unsaved changes.');
        }
      } catch (error) {
        if (context.mounted) {
          AleraToast.show(context, message: error.toString(), tone: .error);
        }
        return;
      }
    } else {
      tabsToDiscard.addAll(dirtyTabs.map((tab) => tab.id));
    }
  }
  if (!context.mounted) {
    return;
  }
  if (dependencies.isNotEmpty) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Dependent Automations',
        message:
            '${dependencies.map((dependency) => '${dependency.name}: ${dependency.activeRuns} active runs').join('\n')}\n\nContinuing pauses these automations when needed and cancels all of their active runs. Their history is preserved. Targets referring to this workspace will need to be changed before resuming.',
        confirmLabel: 'Pause And Continue',
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
  }
  try {
    if (dependencyRuntime != null && dependencies.isNotEmpty) {
      await dependencyRuntime.pauseRemovalDependencies(
        workspace.id,
        dependencies,
      );
    }
    for (final tabId in tabsToDiscard) {
      await registry.discard(tabId);
    }
    await ref
        .read(workbenchControllerProvider.notifier)
        .deleteWorkspace(
          project: project,
          workspace: workspace,
          deleteBranch: decision.deleteBranch,
          activeWorkspaceId: ref
              .read(workbenchControllerProvider)
              .activeWorkspaceId,
        );
    if (context.mounted) {
      AleraToast.show(context, message: 'Workspace removed', tone: .success);
    }
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(context, message: error.toString(), tone: .error);
    }
  }
}

String _workspaceStorageTimestamp(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
