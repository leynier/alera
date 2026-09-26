import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = .utc(2026, 9, 24);

void main() {
  group('slept workspace', () {
    test('lists like a workspace whose terminals were closed', () {
      final slept = _tab('t-slept', 'w-slept');
      final closed = _tab('t-closed', 'w-closed', kind: .editor);
      final state = _state(
        tabs: <WorkspaceTabRecord>[slept, closed],
        sleptTabIds: <String, List<String>>{
          'w-slept': <String>['t-slept'],
        },
      );

      final rows = buildSidebarRows(
        state,
        agentStatuses: <String, AgentStatusEntry>{
          slept.terminalSessionId: _status(slept),
        },
      ).whereType<WorkbenchWorkspaceRow>();

      for (final row in rows) {
        expect(row.hasTerminalTabs, isFalse, reason: row.workspace.id);
        expect(row.agentRuns, isEmpty, reason: row.workspace.id);
      }
      expect(rows.map((row) => row.workspace.id), hasLength(2));
    });

    test('drops out of the active filter', () {
      final state = _state(
        tabs: <WorkspaceTabRecord>[
          _tab('t-slept', 'w-slept'),
          _tab('t-closed', 'w-closed'),
        ],
        sleptTabIds: <String, List<String>>{
          'w-slept': <String>['t-slept'],
        },
        showActiveWorkspacesOnly: true,
      );

      expect(workspaceOrderOfRows(buildSidebarRows(state)), <String>[
        'w-closed',
      ]);
      expect(countVisibleWorkspaces(state), 1);
    });

    test('still shows a terminal opened after the sleep', () {
      final spawned = _tab('t-spawned', 'w-slept');
      final state = _state(
        tabs: <WorkspaceTabRecord>[_tab('t-slept', 'w-slept'), spawned],
        sleptTabIds: <String, List<String>>{
          'w-slept': <String>['t-slept'],
        },
      );

      final row =
          buildSidebarRows(
            state,
            agentStatuses: <String, AgentStatusEntry>{
              spawned.terminalSessionId: _status(spawned),
            },
          ).whereType<WorkbenchWorkspaceRow>().firstWhere(
            (row) => row.workspace.id == 'w-slept',
          );

      expect(row.hasTerminalTabs, isTrue);
      expect(row.agentRuns.map((run) => run.tab.id), <String>['t-spawned']);
    });
  });
}

WorkbenchState _state({
  required List<WorkspaceTabRecord> tabs,
  required Map<String, List<String>> sleptTabIds,
  bool showActiveWorkspacesOnly = false,
}) {
  final project = Project(
    id: 'p-alera',
    name: 'alera',
    repoPath: '/repo/p-alera',
    createdAt: _now,
    updatedAt: _now,
  );
  final workspaces = <Workspace>[
    for (final id in <String>['w-closed', 'w-slept'])
      Workspace(
        id: id,
        projectId: project.id,
        name: id,
        branch: id,
        path: '/repo/p-alera/$id',
        createdAt: _now,
        updatedAt: _now,
        kind: .linked,
        status: .active,
      ),
  ];
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{project.id: workspaces},
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      for (final workspace in workspaces)
        workspace.id: <WorkspaceTabRecord>[
          for (final tab in tabs)
            if (tab.workspaceId == workspace.id) tab,
        ],
    },
    sleptTabIdsByWorkspaceId: sleptTabIds,
    viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
      showActiveWorkspacesOnly: showActiveWorkspacesOnly,
    ),
    bootstrapped: true,
  );
}

WorkspaceTabRecord _tab(
  String id,
  String workspaceId, {
  WorkspaceTabKind kind = WorkspaceTabKind.terminal,
}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: kind,
    title: id,
    createdAt: _now,
    updatedAt: _now,
  );
}

AgentStatusEntry _status(WorkspaceTabRecord tab) {
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    agentType: .codex,
    state: .done,
    prompt: 'done',
    updatedAt: _now,
    stateStartedAt: _now,
  );
}
