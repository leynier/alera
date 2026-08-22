import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _t0 = DateTime.utc(2026, 5, 1);

void main() {
  test(
    'workspace glyph prefers a later working agent over an earlier done one',
    () {
      final project = Project(
        id: 'p-alera',
        name: 'alera',
        repoPath: '/repo/p-alera',
        createdAt: _t0,
        updatedAt: _t0,
      );
      final workspace = Workspace(
        id: 'w-alera-main',
        projectId: project.id,
        name: 'Main',
        branch: 'main',
        path: '/repo/p-alera/w-alera-main',
        createdAt: _t0,
        updatedAt: _t0,
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      );
      final first = _tab('t-1', workspace.id);
      final second = _tab('t-2', workspace.id);
      final state = WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[first, second],
        },
        viewPrefs: WorkbenchViewPrefs.defaults,
        bootstrapped: true,
      );

      final rows = buildSidebarRows(
        state,
        agentStatuses: <String, AgentStatusEntry>{
          first.terminalSessionId: _status(first, AgentStatusState.done),
          second.terminalSessionId: _status(second, AgentStatusState.working),
        },
      );
      final main = rows.whereType<WorkbenchWorkspaceRow>().single;

      expect(main.agentRuns.map((run) => run.tab.id), <String>['t-1', 't-2']);
      expect(main.aggregateStatus?.state, AgentStatusState.working);
      expect(main.aggregateStatus?.tabId, 't-2');
    },
  );
}

WorkspaceTabRecord _tab(String id, String workspaceId) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: WorkspaceTabKind.terminal,
    title: id,
    createdAt: _t0,
    updatedAt: _t0,
  );
}

AgentStatusEntry _status(WorkspaceTabRecord tab, AgentStatusState state) {
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    agentType: AgentType.codex,
    state: state,
    prompt: state.name,
    updatedAt: _t0,
    stateStartedAt: _t0,
  );
}
