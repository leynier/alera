import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _t0 = DateTime.utc(2026, 5, 1);

Project _project(String id, String name, {int recencyOffset = 0}) {
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/$id',
    createdAt: _t0,
    updatedAt: _t0.add(Duration(days: recencyOffset)),
  );
}

Workspace _workspace(
  String id,
  String projectId,
  String name,
  String branch, {
  WorkspaceKind kind = WorkspaceKind.linked,
  int recencyOffset = 0,
  String? sourceBranch,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: name,
    branch: branch,
    path: '/repo/$projectId/$id',
    createdAt: _t0,
    updatedAt: _t0.add(Duration(days: recencyOffset)),
    kind: kind,
    status: WorkspaceStatus.active,
    sourceBranch: sourceBranch,
  );
}

WorkspaceTabRecord _tab(
  String id,
  String workspaceId,
  String title, {
  WorkspaceTabKind kind = WorkspaceTabKind.terminal,
}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: kind,
    title: title,
    createdAt: _t0,
    updatedAt: _t0,
  );
}

WorkbenchState _fixtureState({
  WorkbenchViewPrefs? prefs,
  String? activeWorkspaceId = 'w-alera-main',
  String searchQuery = '',
}) {
  final resolvedPrefs =
      prefs ??
      WorkbenchViewPrefs.defaults.copyWith(
        // Default behaviour mirrors the controller: activating a workspace
        // also expands it so its agent runs are visible.
        expandedWorkspaceIds: <String>{?activeWorkspaceId},
      );
  final alera = _project('p-alera', 'alera', recencyOffset: 2);
  final orca = _project('p-orca', 'orca', recencyOffset: 5);
  final aleraMain = _workspace(
    'w-alera-main',
    alera.id,
    'Main',
    'main',
    kind: WorkspaceKind.main,
    recencyOffset: 1,
  );
  final aleraFeature = _workspace(
    'w-alera-feature',
    alera.id,
    'feature',
    'feature/x',
    recencyOffset: 4,
    sourceBranch: 'main',
  );
  final orcaMain = _workspace(
    'w-orca-main',
    orca.id,
    'Main',
    'develop',
    kind: WorkspaceKind.main,
    recencyOffset: 3,
  );
  return WorkbenchState(
    projects: <Project>[alera, orca],
    workspacesByProject: <String, List<Workspace>>{
      alera.id: <Workspace>[aleraMain, aleraFeature],
      orca.id: <Workspace>[orcaMain],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      aleraMain.id: <WorkspaceTabRecord>[
        _tab('t-1', aleraMain.id, 'Terminal 1'),
        _tab('t-2', aleraMain.id, 'Terminal 2'),
        _tab('e-1', aleraMain.id, 'Editor 1', kind: WorkspaceTabKind.editor),
      ],
    },
    viewPrefs: resolvedPrefs,
    activeProjectId: alera.id,
    activeWorkspaceId: activeWorkspaceId,
    searchQuery: searchQuery,
    bootstrapped: true,
  );
}

Map<String, AgentStatusEntry> _agentStatuses(
  WorkbenchState state,
  List<String> tabIds,
) {
  final selectedIds = tabIds.toSet();
  final statuses = <String, AgentStatusEntry>{};
  for (final tabs in state.tabsByWorkspace.values) {
    for (final tab in tabs) {
      if (!selectedIds.contains(tab.id)) {
        continue;
      }
      statuses[tab.terminalSessionId] = AgentStatusEntry(
        terminalSessionId: tab.terminalSessionId,
        workspaceId: tab.workspaceId,
        tabId: tab.id,
        agentType: AgentType.codex,
        state: AgentStatusState.working,
        prompt: 'Run ${tab.title}',
        updatedAt: _t0,
        stateStartedAt: _t0,
      );
    }
  }
  return statuses;
}

void main() {
  group('buildSidebarRows · group by project', () {
    test('emits project headers, workspace rows and agent-run rows', () {
      final state = _fixtureState();
      final rows = buildSidebarRows(
        state,
        agentStatuses: _agentStatuses(state, <String>['t-1', 't-2']),
      );
      // alera header → Main + 2 agent runs + feature, orca header → Main
      expect(rows, hasLength(7));
      expect(rows[0], isA<WorkbenchProjectHeaderRow>());
      expect((rows[0] as WorkbenchProjectHeaderRow).project.name, 'alera');
      expect(rows[1], isA<WorkbenchWorkspaceRow>());
      expect((rows[1] as WorkbenchWorkspaceRow).workspace.name, 'Main');
      expect((rows[1] as WorkbenchWorkspaceRow).showProjectChip, isFalse);
      expect(rows[2], isA<SidebarAgentRunRow>());
      expect(rows[3], isA<SidebarAgentRunRow>());
      expect(rows[4], isA<WorkbenchWorkspaceRow>());
      expect((rows[4] as WorkbenchWorkspaceRow).workspace.name, 'feature');
      expect(rows[5], isA<WorkbenchProjectHeaderRow>());
      expect((rows[5] as WorkbenchProjectHeaderRow).project.name, 'orca');
      expect(rows[6], isA<WorkbenchWorkspaceRow>());
      expect((rows[6] as WorkbenchWorkspaceRow).workspace.name, 'Main');
    });

    test('main worktree is pinned to the top regardless of name sort', () {
      // 'feature' would normally come before 'main' alphabetically — main wins.
      final rows = buildSidebarRows(_fixtureState());
      final aleraWorkspaces = rows
          .whereType<WorkbenchWorkspaceRow>()
          .where((r) => r.project.id == 'p-alera')
          .toList();
      expect(aleraWorkspaces.first.workspace.isMain, isTrue);
    });

    test('collapsed project hides its workspaces', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        collapsedProjectIds: <String>{'p-alera'},
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      expect(
        rows.whereType<WorkbenchWorkspaceRow>().any(
          (r) => r.project.id == 'p-alera',
        ),
        isFalse,
      );
      // orca header + orca workspace still render.
      expect(rows.whereType<WorkbenchProjectHeaderRow>(), hasLength(2));
    });

    test('positive selection shows only the chosen projects', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        selectedProjectIds: <String>{'p-alera'},
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      final headers = rows.whereType<WorkbenchProjectHeaderRow>().toList();
      expect(headers, hasLength(1));
      expect(headers.single.project.id, 'p-alera');
    });

    test('selecting an unknown id keeps the list empty but does not throw', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        selectedProjectIds: <String>{'p-ghost'},
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      expect(rows.whereType<WorkbenchProjectHeaderRow>(), isEmpty);
      expect(rows.whereType<WorkbenchWorkspaceRow>(), isEmpty);
    });

    test('recent sort orders projects by updatedAt desc', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        projectSort: WorkbenchSortBy.recent,
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      final headers = rows.whereType<WorkbenchProjectHeaderRow>().toList();
      expect(headers.first.project.name, 'orca');
      expect(headers.last.project.name, 'alera');
    });

    test('search can match a workspace source branch', () {
      final rows = buildSidebarRows(_fixtureState(searchQuery: 'main'));
      final workspaces = rows.whereType<WorkbenchWorkspaceRow>().toList();

      expect(
        workspaces.any((row) => row.workspace.id == 'w-alera-feature'),
        isTrue,
      );
    });

    test('name sort compares linked workspaces alphabetically', () {
      final project = _project('p-alpha', 'alpha');
      final zebra = _workspace('w-zebra', project.id, 'zebra', 'z');
      final beta = _workspace('w-beta', project.id, 'beta', 'b');
      final state = WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[zebra, beta],
        },
        viewPrefs: WorkbenchViewPrefs.defaults,
        bootstrapped: true,
      );

      final rows = buildSidebarRows(state);
      final names = rows
          .whereType<WorkbenchWorkspaceRow>()
          .map((row) => row.workspace.name)
          .toList();

      expect(names, <String>['beta', 'zebra']);
    });

    test(
      'recent workspace sort keeps main pinned and sorts linked workspaces',
      () {
        final prefs = WorkbenchViewPrefs.defaults.copyWith(
          workspaceSort: WorkbenchSortBy.recent,
        );
        final project = _project('p-alpha', 'alpha');
        final main = _workspace(
          'w-main',
          project.id,
          'Main',
          'main',
          kind: WorkspaceKind.main,
          recencyOffset: 0,
        );
        final stale = _workspace(
          'w-stale',
          project.id,
          'stale',
          'feature/stale',
          recencyOffset: 1,
        );
        final fresh = _workspace(
          'w-fresh',
          project.id,
          'fresh',
          'feature/fresh',
          recencyOffset: 3,
        );
        final state = WorkbenchState(
          projects: <Project>[project],
          workspacesByProject: <String, List<Workspace>>{
            project.id: <Workspace>[main, stale, fresh],
          },
          viewPrefs: prefs,
          bootstrapped: true,
        );

        final rows = buildSidebarRows(state);
        final ids = rows
            .whereType<WorkbenchWorkspaceRow>()
            .map((row) => row.workspace.id)
            .toList();

        expect(ids, <String>['w-main', 'w-fresh', 'w-stale']);
      },
    );
  });

  group('buildSidebarRows · group by none', () {
    test('flat list contains every workspace with showProjectChip', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      final workspaces = rows.whereType<WorkbenchWorkspaceRow>().toList();
      expect(workspaces, hasLength(3));
      expect(workspaces.every((r) => r.showProjectChip), isTrue);
      // No header rows in flat mode.
      expect(rows.whereType<WorkbenchProjectHeaderRow>(), isEmpty);
    });

    test('agent runs appear when the workspace is in the expansion set', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        expandedWorkspaceIds: <String>{'w-alera-main'},
      );
      final state = _fixtureState(prefs: prefs);
      final rows = buildSidebarRows(
        state,
        agentStatuses: _agentStatuses(state, <String>['t-1', 't-2']),
      );
      expect(rows.whereType<SidebarAgentRunRow>(), hasLength(2));
    });

    test('terminal tabs without agent status stay out of the sidebar', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        expandedWorkspaceIds: <String>{'w-alera-main'},
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      expect(rows.whereType<SidebarAgentRunRow>(), isEmpty);
    });

    test('non-terminal workspace tabs stay out of the sidebar', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        expandedWorkspaceIds: <String>{'w-alera-main'},
      );
      final state = _fixtureState(prefs: prefs);
      final rows = buildSidebarRows(
        state,
        agentStatuses: _agentStatuses(state, <String>['e-1']),
      );
      expect(rows.whereType<SidebarAgentRunRow>(), isEmpty);
    });

    test('workspace without an expansion entry shows no agent runs', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        // expandedWorkspaceIds is empty — no workspace should reveal its
        // agent runs even though one is active in the state fixture.
      );
      final state = _fixtureState(prefs: prefs);
      final rows = buildSidebarRows(
        state,
        agentStatuses: _agentStatuses(state, <String>['t-1']),
      );
      expect(rows.whereType<SidebarAgentRunRow>(), isEmpty);
    });

    test('recent sort orders workspaces by updatedAt desc', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        workspaceSort: WorkbenchSortBy.recent,
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      final ids = rows
          .whereType<WorkbenchWorkspaceRow>()
          .map((r) => r.workspace.id)
          .toList();
      // alera-feature (offset 4) > orca-main (3) > alera-main (1)
      expect(ids, <String>['w-alera-feature', 'w-orca-main', 'w-alera-main']);
    });
  });

  group('buildSidebarRows · search', () {
    test('matches against workspace name, branch and source branch', () {
      final rows = buildSidebarRows(_fixtureState(searchQuery: 'feature'));
      final workspaces = rows.whereType<WorkbenchWorkspaceRow>().toList();
      expect(workspaces, hasLength(1));
      expect(workspaces.single.workspace.id, 'w-alera-feature');
    });

    test('project name match surfaces all its workspaces', () {
      final rows = buildSidebarRows(_fixtureState(searchQuery: 'orca'));
      final workspaces = rows.whereType<WorkbenchWorkspaceRow>().toList();
      expect(workspaces, hasLength(1));
      expect(workspaces.single.workspace.id, 'w-orca-main');
    });
  });

  group('countVisibleWorkspaces', () {
    test('counts every visible workspace ignoring group collapse', () {
      final state = _fixtureState();
      expect(countVisibleWorkspaces(state), 3);
    });

    test('respects positive project selection', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        selectedProjectIds: <String>{'p-alera'},
      );
      // alera has 2 workspaces, orca is filtered out.
      expect(countVisibleWorkspaces(_fixtureState(prefs: prefs)), 2);
    });

    test('respects search', () {
      expect(countVisibleWorkspaces(_fixtureState(searchQuery: 'feature')), 1);
    });

    test('search also counts source-branch matches', () {
      expect(countVisibleWorkspaces(_fixtureState(searchQuery: 'main')), 3);
    });
  });
}
