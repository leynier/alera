import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

abstract interface class AgentNotificationWindowActivator {
  Future<void> showAndFocus();
}

abstract interface class AgentNotificationWorkbenchNavigator {
  WorkbenchState get state;

  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  });

  void setActiveTab({required String workspaceId, required String tabId});
}

abstract interface class AgentNotificationTerminalFocusRequester {
  void requestTerminalFocus({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  });
}

class AgentStatusNotificationActivationService({
  required AgentNotificationWindowActivator windowActivator,
  required AgentNotificationWorkbenchNavigator navigator,
  required AgentNotificationTerminalFocusRequester terminalFocusRequester,
}) {
  this
    : _dependencies = _AgentStatusNotificationActivationDependencies(
        windowActivator: windowActivator,
        navigator: navigator,
        terminalFocusRequester: terminalFocusRequester,
      );

  final _AgentStatusNotificationActivationDependencies _dependencies;

  Future<void> activatePayload(String? rawPayload) async {
    final payload = decodeAgentStatusNotificationPayload(rawPayload);
    if (payload == null) {
      return;
    }
    await _dependencies.windowActivator.showAndFocus();
    final state = _dependencies.navigator.state;
    final workspace = _findWorkspace(state, payload.workspaceId);
    if (workspace == null) {
      return;
    }
    final project = _findProject(state, workspace.projectId);
    if (project == null) {
      return;
    }
    final tab = _findTab(state, payload.workspaceId, payload.tabId);
    if (tab == null) {
      return;
    }
    await _dependencies.navigator.selectWorkspace(
      project: project,
      workspace: workspace,
    );
    _dependencies.navigator.setActiveTab(
      workspaceId: workspace.id,
      tabId: tab.id,
    );
    _dependencies.terminalFocusRequester.requestTerminalFocus(
      workspace: workspace,
      tab: tab,
    );
  }

  Workspace? _findWorkspace(WorkbenchState state, String workspaceId) {
    for (final workspaces in state.workspacesByProject.values) {
      for (final workspace in workspaces) {
        if (workspace.id == workspaceId) {
          return workspace;
        }
      }
    }
    return null;
  }

  Project? _findProject(WorkbenchState state, String projectId) {
    for (final project in state.projects) {
      if (project.id == projectId) {
        return project;
      }
    }
    return null;
  }

  WorkspaceTabRecord? _findTab(
    WorkbenchState state,
    String workspaceId,
    String tabId,
  ) {
    for (final tab in state.tabsFor(workspaceId)) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }
}

class const _AgentStatusNotificationActivationDependencies({
  required final AgentNotificationWindowActivator windowActivator,
  required final AgentNotificationWorkbenchNavigator navigator,
  required final AgentNotificationTerminalFocusRequester terminalFocusRequester,
});
