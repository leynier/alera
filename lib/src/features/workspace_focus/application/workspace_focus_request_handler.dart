import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

/// What a runtime focus request needs from the desktop workbench.
abstract interface class WorkspaceFocusWorkbench {
  WorkbenchState get state;

  /// Later workbench states, so a request can wait for a workspace the
  /// sidebar has not loaded yet.
  Stream<WorkbenchState> get stateChanges;

  /// Leaves full-page views such as the Run Board so the workbench is visible.
  void closeOverlays();

  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  });
}

/// The workspace id a `workspaceFocusRequested` event names, if any.
String? workspaceFocusRequestId(RuntimeHostEvent event) {
  if (event.name != aleraWorkspaceFocusRequestedEvent) {
    return null;
  }
  final workspaceId = event.payload['workspaceId'];
  return workspaceId is String && workspaceId.trim().isNotEmpty
      ? workspaceId.trim()
      : null;
}

/// Selects and shows a workspace the runtime asked the app to focus.
///
/// Selection goes through [WorkspaceFocusWorkbench.selectWorkspace], the same
/// path as a sidebar click, so open tabs and terminals are kept as they are.
/// A newer request supersedes one still waiting for its workspace.
class WorkspaceFocusRequestHandler({
  required final AgentNotificationWindowActivator windowActivator,
  required final WorkspaceFocusWorkbench workbench,
  final Duration workspaceWait = const Duration(seconds: 10),
}) {
  int _generation = 0;

  /// Returns whether the workspace ended up selected.
  Future<bool> focus(String workspaceId) async {
    final generation = ++_generation;
    final target = await _awaitTarget(workspaceId);
    if (target == null || generation != _generation) {
      return false;
    }
    await windowActivator.showAndFocus();
    if (generation != _generation) {
      return false;
    }
    workbench.closeOverlays();
    await workbench.selectWorkspace(
      project: target.project,
      workspace: target.workspace,
    );
    return workbench.state.activeWorkspaceId == workspaceId;
  }

  Future<_FocusTarget?> _awaitTarget(String workspaceId) async {
    final current = _resolve(workbench.state, workspaceId);
    if (current != null) {
      return current;
    }
    try {
      return await workbench.stateChanges
          .map((state) => _resolve(state, workspaceId))
          .firstWhere((target) => target != null)
          .timeout(workspaceWait);
    } on TimeoutException {
      return null;
    } on StateError {
      // The workbench went away before the workspace showed up.
      return null;
    }
  }

  _FocusTarget? _resolve(WorkbenchState state, String workspaceId) {
    if (!state.bootstrapped) {
      return null;
    }
    for (final project in state.projects) {
      for (final workspace in state.workspacesFor(project.id)) {
        if (workspace.id == workspaceId) {
          return (project: project, workspace: workspace);
        }
      }
    }
    return null;
  }
}

typedef _FocusTarget = ({Project project, Workspace workspace});
