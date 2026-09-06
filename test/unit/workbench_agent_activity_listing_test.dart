import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = .utc(2026, 5, 1);

Project _project(String id, String name, {int recencyOffset = 0}) {
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/$id',
    createdAt: _now,
    updatedAt: _now.add(Duration(days: recencyOffset)),
  );
}

Workspace _workspace(
  String id,
  String projectId,
  String name, {
  int recencyOffset = 0,
  String? parentWorkspaceId,
  bool isPinned = false,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: name,
    branch: id,
    path: '/repo/$projectId/$id',
    createdAt: _now,
    updatedAt: _now.add(Duration(days: recencyOffset)),
    kind: .linked,
    status: .active,
    parentWorkspaceId: parentWorkspaceId,
    isPinned: isPinned,
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

AgentStatusEntry _status(WorkspaceTabRecord tab, AgentStatusState state) {
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    agentType: AgentType.claude,
    state: state,
    prompt: state.name,
    updatedAt: _now,
    stateStartedAt: _now,
  );
}

WorkbenchState _activityState(
  WorkbenchViewPrefs prefs, {
  String? activeWorkspaceId,
}) {
  final alera = _project('p-alera', 'alera');
  final orca = _project('p-orca', 'orca');
  final waiting = _workspace('w-waiting', alera.id, 'aaa-waiting');
  final working = _workspace('w-working', alera.id, 'bbb-working');
  final idle = _workspace('w-idle', orca.id, 'ccc-idle');
  return WorkbenchState(
    projects: <Project>[alera, orca],
    workspacesByProject: <String, List<Workspace>>{
      alera.id: <Workspace>[working, waiting],
      orca.id: <Workspace>[idle],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      waiting.id: <WorkspaceTabRecord>[_tab('t-w', waiting.id)],
      working.id: <WorkspaceTabRecord>[_tab('t-x', working.id)],
    },
    viewPrefs: prefs,
    activeWorkspaceId: activeWorkspaceId,
    bootstrapped: true,
  );
}

Map<String, AgentStatusEntry> _activityStatuses(WorkbenchState state) {
  return <String, AgentStatusEntry>{
    for (final tab in state.tabsByWorkspace.values.expand((tabs) => tabs))
      tab.terminalSessionId: _status(
        tab,
        tab.workspaceId == 'w-waiting'
            ? AgentStatusState.waiting
            : AgentStatusState.working,
      ),
  };
}

List<String> _workspaceIds(List<WorkbenchSidebarRow> rows) {
  return rows
      .whereType<WorkbenchWorkspaceRow>()
      .map((row) => row.workspace.id)
      .toList();
}

void main() {
  test('needs-you workspaces rank above working and inactive workspaces', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      groupBy: .none,
      workspaceSort: .activity,
    );
    final state = _activityState(prefs);

    expect(
      _workspaceIds(
        buildSidebarRows(
          state,
          agentStatuses: _activityStatuses(state),
          now: _now,
        ),
      ),
      <String>['w-waiting', 'w-working', 'w-idle'],
    );
  });

  test('active project headers rank above inactive projects', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(projectSort: .activity);
    final state = _activityState(prefs);
    final headers = buildSidebarRows(
      state,
      agentStatuses: _activityStatuses(state),
      now: _now,
    ).whereType<WorkbenchProjectHeaderRow>();

    expect(headers.first.project.id, 'p-alera');
  });

  test('active projects rank by their most urgent workspace', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(projectSort: .activity);
    final alpha = _project('p-alpha', 'alpha');
    final zeta = _project('p-zeta', 'zeta');
    final working = _workspace('w-working', alpha.id, 'working');
    final waiting = _workspace('w-waiting', zeta.id, 'waiting');
    final workingTab = _tab('t-working', working.id);
    final waitingTab = _tab('t-waiting', waiting.id);
    final state = WorkbenchState(
      projects: <Project>[alpha, zeta],
      workspacesByProject: <String, List<Workspace>>{
        alpha.id: <Workspace>[working],
        zeta.id: <Workspace>[waiting],
      },
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        working.id: <WorkspaceTabRecord>[workingTab],
        waiting.id: <WorkspaceTabRecord>[waitingTab],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );
    final statuses = <String, AgentStatusEntry>{
      workingTab.terminalSessionId: _status(workingTab, .working),
      waitingTab.terminalSessionId: _status(waitingTab, .waiting),
    };

    expect(
      buildSidebarRows(
        state,
        agentStatuses: statuses,
        now: _now,
      ).whereType<WorkbenchProjectHeaderRow>().map((row) => row.project.id),
      <String>['p-zeta', 'p-alpha'],
    );
  });

  test('inactive projects sort alphabetically', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(projectSort: .activity);
    final zeta = _project('p-zeta', 'zeta', recencyOffset: 10);
    final alpha = _project('p-alpha', 'alpha');
    final state = WorkbenchState(
      projects: <Project>[zeta, alpha],
      workspacesByProject: <String, List<Workspace>>{
        zeta.id: <Workspace>[_workspace('w-zeta', zeta.id, 'zeta')],
        alpha.id: <Workspace>[_workspace('w-alpha', alpha.id, 'alpha')],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );

    expect(
      buildSidebarRows(state)
          .whereType<WorkbenchProjectHeaderRow>()
          .map((row) => row.project.id),
      <String>['p-alpha', 'p-zeta'],
    );
  });

  test('the selected workspace does not override strict activity order', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      groupBy: .none,
      workspaceSort: .activity,
    );
    final state = _activityState(prefs, activeWorkspaceId: 'w-working');

    expect(
      _workspaceIds(
        buildSidebarRows(
          state,
          agentStatuses: _activityStatuses(state),
          now: _now,
        ),
      ),
      <String>['w-waiting', 'w-working', 'w-idle'],
    );
  });

  test('inactive workspaces ignore recency and sort alphabetically', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      groupBy: .none,
      workspaceSort: .activity,
    );
    final project = _project('p-alera', 'alera');
    final alpha = _workspace('w-a', project.id, 'aaa');
    final beta = _workspace('w-b', project.id, 'bbb');
    final state = WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[alpha, beta],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );

    expect(
      _workspaceIds(
        buildSidebarRows(
          state,
          lastActivityByWorkspaceId: <String, DateTime>{
            beta.id: _now.add(const Duration(days: 1)),
          },
          now: _now,
        ),
      ),
      <String>['w-a', 'w-b'],
    );
  });

  test('an open terminal is active without a live agent status', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      groupBy: .none,
      workspaceSort: .activity,
    );
    final project = _project('p-alera', 'alera');
    final active = _workspace('w-active', project.id, 'zebra');
    final inactive = _workspace('w-inactive', project.id, 'alpha');
    final state = WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[inactive, active],
      },
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        active.id: <WorkspaceTabRecord>[_tab('t-active', active.id)],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );

    expect(_workspaceIds(buildSidebarRows(state)), <String>[
      'w-active',
      'w-inactive',
    ]);
  });

  test('an open Codex tab is active without a live agent status', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      groupBy: .none,
      workspaceSort: .activity,
    );
    final project = _project('p-alera', 'alera');
    final active = _workspace('w-active', project.id, 'zebra');
    final inactive = _workspace('w-inactive', project.id, 'alpha');
    final state = WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[inactive, active],
      },
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        active.id: <WorkspaceTabRecord>[_tab('c-active', active.id)],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );

    expect(_workspaceIds(buildSidebarRows(state)), <String>[
      'w-active',
      'w-inactive',
    ]);
  });

  test('a waiting Codex tab outranks a working terminal', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      groupBy: .none,
      workspaceSort: .activity,
    );
    final project = _project('p-alera', 'alera');
    final working = _workspace('w-working', project.id, 'alpha');
    final waiting = _workspace('w-waiting', project.id, 'zeta');
    final workingTab = _tab('t-working', working.id);
    final waitingTab = _tab('c-waiting', waiting.id);
    final state = WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[working, waiting],
      },
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        working.id: <WorkspaceTabRecord>[workingTab],
        waiting.id: <WorkspaceTabRecord>[waitingTab],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );
    final statuses = <String, AgentStatusEntry>{
      workingTab.terminalSessionId: _status(workingTab, .working),
      'codex:${waitingTab.id}': _status(waitingTab, .waiting),
    };

    expect(
      _workspaceIds(
        buildSidebarRows(state, agentStatuses: statuses, now: _now),
      ),
      <String>['w-waiting', 'w-working'],
    );
  });

  test('global pinned section keeps active workspaces first', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      workspaceSort: .activity,
    );
    final alpha = _project('p-alpha', 'alpha');
    final zeta = _project('p-zeta', 'zeta');
    final inactive = _workspace(
      'w-inactive',
      alpha.id,
      'alpha',
      isPinned: true,
    );
    final active = _workspace('w-active', zeta.id, 'zebra', isPinned: true);
    final state = WorkbenchState(
      projects: <Project>[alpha, zeta],
      workspacesByProject: <String, List<Workspace>>{
        alpha.id: <Workspace>[inactive],
        zeta.id: <Workspace>[active],
      },
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        active.id: <WorkspaceTabRecord>[_tab('t-active', active.id)],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );

    expect(
      buildSidebarRows(state)
          .whereType<WorkbenchWorkspaceRow>()
          .where((row) => row.isPinnedCopy)
          .map((row) => row.workspace.id),
      <String>['w-active', 'w-inactive'],
    );
  });

  test('active descendants promote and rank their workspace trees', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      groupBy: .none,
      workspaceSort: .activity,
    );
    final project = _project('p-tree', 'tree');
    final workingRoot = _workspace('w-working-root', project.id, 'alpha-root');
    final workingChild = _workspace(
      'w-working-child',
      project.id,
      'working-child',
      parentWorkspaceId: workingRoot.id,
    );
    final waitingRoot = _workspace('w-waiting-root', project.id, 'zeta-root');
    final waitingChild = _workspace(
      'w-waiting-child',
      project.id,
      'waiting-child',
      parentWorkspaceId: waitingRoot.id,
    );
    final inactiveRoot = _workspace('w-inactive-root', project.id, 'beta-root');
    final workingTab = _tab('t-working', workingChild.id);
    final waitingTab = _tab('t-waiting', waitingChild.id);
    final state = WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[
          workingRoot,
          workingChild,
          waitingRoot,
          waitingChild,
          inactiveRoot,
        ],
      },
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        workingChild.id: <WorkspaceTabRecord>[workingTab],
        waitingChild.id: <WorkspaceTabRecord>[waitingTab],
      },
      viewPrefs: prefs,
      bootstrapped: true,
    );
    final statuses = <String, AgentStatusEntry>{
      workingTab.terminalSessionId: _status(workingTab, .working),
      waitingTab.terminalSessionId: _status(waitingTab, .waiting),
    };

    expect(
      _workspaceIds(
        buildSidebarRows(state, agentStatuses: statuses, now: _now),
      ),
      <String>[
        'w-waiting-root',
        'w-waiting-child',
        'w-working-root',
        'w-working-child',
        'w-inactive-root',
      ],
    );
  });
}
