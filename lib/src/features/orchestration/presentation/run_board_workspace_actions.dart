import 'dart:async';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RunBoardWorkspaceAction { workspace, terminal, diff }

/// Resolve live workspace/tab identities, never paths from the display projection.
VoidCallback? runBoardWorkspaceAction(
  BuildContext context,
  WidgetRef ref,
  String workspaceId,
  RunBoardWorkspaceAction action, {
  String? terminalHandle,
}) {
  final state = ref.watch(workbenchControllerProvider);
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
      (action == RunBoardWorkspaceAction.terminal && tab == null) ||
      (action == RunBoardWorkspaceAction.diff && project.isFolder)) {
    return null;
  }
  return () => unawaited(() async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    try {
      await controller.selectWorkspace(project: project, workspace: workspace);
      if (!context.mounted) return;
      switch (action) {
        case RunBoardWorkspaceAction.workspace:
          break;
        case RunBoardWorkspaceAction.terminal:
          await controller.selectWorkspaceTab(
            workspaceId: workspaceId,
            tabId: tab!.id,
          );
        case RunBoardWorkspaceAction.diff:
          await controller.openGitDiffTab(
            workspace: workspace,
            scope: WorkspaceGitDiffScope.all,
          );
      }
      if (context.mounted) {
        ref.read(runBoardNavigationProvider.notifier).close();
        if (action == RunBoardWorkspaceAction.terminal) {
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
