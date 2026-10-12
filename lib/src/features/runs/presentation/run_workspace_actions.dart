import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RunWorkspaceAction { workspace, terminal, diff }

/// Resolve live workspace/tab identities, never paths from the display projection.
VoidCallback? runWorkspaceAction(
  BuildContext context,
  WidgetRef ref,
  String workspaceId,
  RunWorkspaceAction action, {
  String? terminalHandle,
  bool listen = true,
  bool committedResult = false,
  String? resultBaseSha,
  String? resultCompletionSha,
  String resultSubject = 'Task result',
}) {
  final state = listen
      ? ref.watch(workbenchControllerProvider)
      : ref.read(workbenchControllerProvider);
  final workspace = state.workspacesByProject.values
      .expand((items) => items)
      .where(
        (item) =>
            item.id == workspaceId && item.hostId == 'local' && item.isActive,
      )
      .firstOrNull;
  final project = state.projects
      .where((item) => item.id == workspace?.projectId)
      .firstOrNull;
  final tab = state
      .tabsFor(workspaceId)
      .where(
        (item) =>
            item.kind == WorkspaceTabKind.terminal &&
            item.terminalSessionId == terminalHandle,
      )
      .firstOrNull;
  if (workspace == null ||
      project == null ||
      (action == RunWorkspaceAction.terminal && tab == null) ||
      (action == RunWorkspaceAction.diff && project.isFolder) ||
      (action == RunWorkspaceAction.diff &&
          committedResult &&
          (resultBaseSha == null || resultCompletionSha == null))) {
    return null;
  }
  return () => unawaited(() async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    try {
      await controller.selectWorkspace(project: project, workspace: workspace);
      if (!context.mounted) return;
      switch (action) {
        case RunWorkspaceAction.workspace:
          break;
        case RunWorkspaceAction.terminal:
          await controller.selectWorkspaceTab(
            workspaceId: workspaceId,
            tabId: tab!.id,
          );
        case RunWorkspaceAction.diff:
          if (committedResult) {
            final completionSha = resultCompletionSha!;
            await controller.openGitCommitDiffTab(
              workspace: workspace,
              scope: WorkspaceGitDiffScope.all,
              commitOid: completionSha,
              parentOid: resultBaseSha!,
              compareRef: completionSha.length > 8
                  ? completionSha.substring(0, 8)
                  : completionSha,
              subject: resultSubject,
            );
          } else {
            await controller.openGitDiffTab(
              workspace: workspace,
              scope: WorkspaceGitDiffScope.all,
            );
          }
      }
      if (context.mounted) {
        ref.read(activityNavigationProvider.notifier).close();
        if (action == RunWorkspaceAction.terminal) {
          ref
              .read(terminalRuntimeProvider)
              .sessionFor(workspace: workspace, tab: tab!)
              .requestFocus();
        }
      }
    } on Object catch (error) {
      if (context.mounted) {
        AleraToast.show(
          context,
          message: 'Could not open workspace: $error',
          tone: AleraToastTone.error,
        );
      }
    }
  }());
}
