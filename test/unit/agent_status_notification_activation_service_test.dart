import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentStatusNotificationActivationService', () {
    test(
      'focuses the app, selects workspace, activates tab, and focuses terminal',
      () async {
        final target = _fixture();
        final activator = _FakeWindowActivator();
        final navigator = _FakeNavigator(target.state);
        final focusRequester = _FakeTerminalFocusRequester();
        final service = AgentStatusNotificationActivationService(
          windowActivator: activator,
          navigator: navigator,
          terminalFocusRequester: focusRequester,
        );

        await service.activatePayload(_payload().encode());

        expect(activator.showAndFocusCalls, 1);
        expect(navigator.selectedProjectIds, <String>['project-1']);
        expect(navigator.selectedWorkspaceIds, <String>['workspace-1']);
        expect(navigator.activeTabs, <String, String>{'workspace-1': 'tab-1'});
        expect(focusRequester.focusedTabIds, <String>['tab-1']);
      },
    );

    test(
      'brings the app forward but stops when workspace or tab is missing',
      () async {
        final target = _fixture();
        final activator = _FakeWindowActivator();
        final navigator = _FakeNavigator(
          target.state.copyWith(
            tabsByWorkspace: const <String, List<WorkspaceTabRecord>>{},
          ),
        );
        final focusRequester = _FakeTerminalFocusRequester();
        final service = AgentStatusNotificationActivationService(
          windowActivator: activator,
          navigator: navigator,
          terminalFocusRequester: focusRequester,
        );

        await service.activatePayload(_payload().encode());

        expect(activator.showAndFocusCalls, 1);
        expect(navigator.selectedWorkspaceIds, isEmpty);
        expect(focusRequester.focusedTabIds, isEmpty);
      },
    );

    test('ignores malformed payloads', () async {
      final target = _fixture();
      final activator = _FakeWindowActivator();
      final service = AgentStatusNotificationActivationService(
        windowActivator: activator,
        navigator: _FakeNavigator(target.state),
        terminalFocusRequester: _FakeTerminalFocusRequester(),
      );

      await service.activatePayload('not json');

      expect(activator.showAndFocusCalls, 0);
    });
  });
}

AgentStatusNotificationPayload _payload() {
  return const AgentStatusNotificationPayload(
    terminalSessionId: 'session-1',
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: .codex,
    state: .done,
  );
}

({
  WorkbenchState state,
  Project project,
  Workspace workspace,
  WorkspaceTabRecord tab,
})
_fixture() {
  final now = DateTime.utc(2026, 5, 26, 12);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/workspace/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'main',
    path: '/workspace/alera',
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
  final tab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Codex',
    createdAt: now,
    updatedAt: now,
  );
  return (
    state: WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[workspace],
      },
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        workspace.id: <WorkspaceTabRecord>[tab],
      },
    ),
    project: project,
    workspace: workspace,
    tab: tab,
  );
}

class _FakeWindowActivator implements AgentNotificationWindowActivator {
  int showAndFocusCalls = 0;

  @override
  Future<void> showAndFocus() async {
    showAndFocusCalls++;
  }
}

class _FakeNavigator(var WorkbenchState _state)
    implements AgentNotificationWorkbenchNavigator {
  final List<String> selectedProjectIds = <String>[];
  final List<String> selectedWorkspaceIds = <String>[];
  final Map<String, String> activeTabs = <String, String>{};

  @override
  WorkbenchState get state => _state;

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    selectedProjectIds.add(project.id);
    selectedWorkspaceIds.add(workspace.id);
    _state = _state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
    );
  }

  @override
  void setActiveTab({required String workspaceId, required String tabId}) {
    activeTabs[workspaceId] = tabId;
  }
}

class _FakeTerminalFocusRequester
    implements AgentNotificationTerminalFocusRequester {
  final List<String> focusedTabIds = <String>[];

  @override
  void requestTerminalFocus({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    focusedTabIds.add(tab.id);
  }
}
