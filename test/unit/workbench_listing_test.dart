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
  List<String> tagIds = const <String>[],
  String? parentWorkspaceId,
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
    tagIds: tagIds,
    parentWorkspaceId: parentWorkspaceId,
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
    test('emits project headers and workspace rows', () {
      final state = _fixtureState();
      final rows = buildSidebarRows(
        state,
        agentStatuses: _agentStatuses(state, <String>['t-1', 't-2']),
      );
      // alera header → Main + feature, orca header → Main
      expect(rows, hasLength(5));
      expect(rows[0], isA<WorkbenchProjectHeaderRow>());
      expect((rows[0] as WorkbenchProjectHeaderRow).project.name, 'alera');
      expect(rows[1], isA<WorkbenchWorkspaceRow>());
      expect((rows[1] as WorkbenchWorkspaceRow).workspace.name, 'Main');
      expect((rows[1] as WorkbenchWorkspaceRow).showProjectChip, isFalse);
      expect(rows[2], isA<WorkbenchWorkspaceRow>());
      expect((rows[2] as WorkbenchWorkspaceRow).workspace.name, 'feature');
      expect(rows[3], isA<WorkbenchProjectHeaderRow>());
      expect((rows[3] as WorkbenchProjectHeaderRow).project.name, 'orca');
      expect(rows[4], isA<WorkbenchWorkspaceRow>());
      expect((rows[4] as WorkbenchWorkspaceRow).workspace.name, 'Main');
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

    test('agent statuses do not add separate sidebar rows', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        expandedWorkspaceIds: <String>{'w-alera-main'},
      );
      final state = _fixtureState(prefs: prefs);
      final rows = buildSidebarRows(
        state,
        agentStatuses: _agentStatuses(state, <String>['t-1', 't-2']),
      );
      expect(rows.whereType<WorkbenchWorkspaceRow>(), hasLength(3));
      expect(rows.whereType<WorkbenchProjectHeaderRow>(), isEmpty);
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

  group('buildSidebarRows · tag filter', () {
    WorkbenchState taggedState(WorkbenchViewPrefs prefs) {
      final alera = _project('p-alera', 'alera');
      final orca = _project('p-orca', 'orca');
      final tagged = _workspace(
        'w-tagged',
        alera.id,
        'tagged',
        'feature/tagged',
        tagIds: const <String>['tag-review'],
      );
      final untagged = _workspace('w-plain', alera.id, 'plain', 'feature/p');
      final orcaTagged = _workspace(
        'w-orca',
        orca.id,
        'orca-ws',
        'main',
        tagIds: const <String>['tag-mobile'],
      );
      return WorkbenchState(
        projects: <Project>[alera, orca],
        workspacesByProject: <String, List<Workspace>>{
          alera.id: <Workspace>[tagged, untagged],
          orca.id: <Workspace>[orcaTagged],
        },
        viewPrefs: prefs,
        bootstrapped: true,
      );
    }

    test('empty selection shows every workspace', () {
      final rows = buildSidebarRows(taggedState(WorkbenchViewPrefs.defaults));
      expect(rows.whereType<WorkbenchWorkspaceRow>(), hasLength(3));
    });

    test('OR semantics keep workspaces carrying any selected tag', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        selectedTagIds: <String>{'tag-review', 'tag-mobile'},
      );
      final rows = buildSidebarRows(taggedState(prefs));
      final ids = rows
          .whereType<WorkbenchWorkspaceRow>()
          .map((r) => r.workspace.id)
          .toSet();
      expect(ids, <String>{'w-tagged', 'w-orca'});
    });

    test('projects without matching workspaces hide their header', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        selectedTagIds: <String>{'tag-mobile'},
      );
      final rows = buildSidebarRows(taggedState(prefs));
      final headers = rows.whereType<WorkbenchProjectHeaderRow>().toList();
      expect(headers, hasLength(1));
      expect(headers.single.project.id, 'p-orca');
    });

    test('countVisibleWorkspaces honors the tag filter', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        selectedTagIds: <String>{'tag-review'},
      );
      expect(countVisibleWorkspaces(taggedState(prefs)), 1);
    });
  });

  group('buildSidebarRows · parent-child nesting', () {
    WorkbenchState nestedState(WorkbenchViewPrefs prefs) {
      final alera = _project('p-alera', 'alera');
      final orca = _project('p-orca', 'orca');
      final parent = _workspace('w-parent', alera.id, 'parent', 'main');
      final child = _workspace(
        'w-child',
        alera.id,
        'child',
        'feature/child',
        parentWorkspaceId: 'w-parent',
      );
      final crossProjectChild = _workspace(
        'w-cross',
        orca.id,
        'cross',
        'main',
        parentWorkspaceId: 'w-parent',
      );
      return WorkbenchState(
        projects: <Project>[alera, orca],
        workspacesByProject: <String, List<Workspace>>{
          alera.id: <Workspace>[parent, child],
          orca.id: <Workspace>[crossProjectChild],
        },
        viewPrefs: prefs,
        bootstrapped: true,
      );
    }

    test('children indent under their parent in grouped mode', () {
      final rows = buildSidebarRows(nestedState(WorkbenchViewPrefs.defaults));
      final workspaceRows = rows.whereType<WorkbenchWorkspaceRow>().toList();
      final parent = workspaceRows.firstWhere(
        (r) => r.workspace.id == 'w-parent',
      );
      final child = workspaceRows.firstWhere(
        (r) => r.workspace.id == 'w-child',
      );
      expect(parent.indent, 1);
      expect(parent.visibleChildCount, 1);
      expect(parent.hasVisibleChildren, isTrue);
      expect(child.indent, 2);
      expect(child.visibleChildCount, 0);
    });

    test('cross-project children render at the root of their own group', () {
      final rows = buildSidebarRows(nestedState(WorkbenchViewPrefs.defaults));
      final cross = rows.whereType<WorkbenchWorkspaceRow>().firstWhere(
        (r) => r.workspace.id == 'w-cross',
      );
      expect(cross.indent, 1);
    });

    test('collapsing the parent hides its children', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        collapsedParentWorkspaceIds: <String>{'w-parent'},
      );
      final rows = buildSidebarRows(nestedState(prefs));
      final ids = rows
          .whereType<WorkbenchWorkspaceRow>()
          .map((r) => r.workspace.id)
          .toSet();
      expect(ids, isNot(contains('w-child')));
      final parent = rows.whereType<WorkbenchWorkspaceRow>().firstWhere(
        (r) => r.workspace.id == 'w-parent',
      );
      expect(parent.childrenCollapsed, isTrue);
      expect(parent.visibleChildCount, 1);
    });

    test('a child whose parent is filtered out is promoted to root', () {
      final prefs = WorkbenchViewPrefs.defaults;
      final state = nestedState(prefs);
      final rows = buildSidebarRows(state.copyWith(searchQuery: 'child'));
      final child = rows.whereType<WorkbenchWorkspaceRow>().firstWhere(
        (r) => r.workspace.id == 'w-child',
      );
      expect(child.indent, 1);
    });

    test('children nest in flat mode too', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
      );
      final rows = buildSidebarRows(nestedState(prefs));
      final workspaceRows = rows.whereType<WorkbenchWorkspaceRow>().toList();
      final parent = workspaceRows.firstWhere(
        (r) => r.workspace.id == 'w-parent',
      );
      final child = workspaceRows.firstWhere(
        (r) => r.workspace.id == 'w-child',
      );
      final cross = workspaceRows.firstWhere(
        (r) => r.workspace.id == 'w-cross',
      );
      expect(parent.indent, 0);
      expect(child.indent, 1);
      // Flat mode is one sibling group, so cross-project children nest too.
      expect(cross.indent, 1);
    });
  });

  group('buildSidebarRows · agent activity sort', () {
    WorkbenchState activityState(
      WorkbenchViewPrefs prefs, {
      String? activeWorkspaceId,
    }) {
      final alera = _project('p-alera', 'alera');
      final orca = _project('p-orca', 'orca');
      final waiting = _workspace('w-waiting', alera.id, 'aaa-waiting', 'w');
      final working = _workspace('w-working', alera.id, 'bbb-working', 'x');
      final idle = _workspace('w-idle', orca.id, 'ccc-idle', 'y');
      return WorkbenchState(
        projects: <Project>[alera, orca],
        workspacesByProject: <String, List<Workspace>>{
          alera.id: <Workspace>[working, waiting],
          orca.id: <Workspace>[idle],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          waiting.id: <WorkspaceTabRecord>[_tab('t-w', waiting.id, 'T')],
          working.id: <WorkspaceTabRecord>[_tab('t-x', working.id, 'T')],
        },
        viewPrefs: prefs,
        activeWorkspaceId: activeWorkspaceId,
        bootstrapped: true,
      );
    }

    Map<String, AgentStatusEntry> activityStatuses(WorkbenchState state) {
      final statuses = <String, AgentStatusEntry>{};
      for (final tabs in state.tabsByWorkspace.values) {
        for (final tab in tabs) {
          statuses[tab.terminalSessionId] = AgentStatusEntry(
            terminalSessionId: tab.terminalSessionId,
            workspaceId: tab.workspaceId,
            tabId: tab.id,
            agentType: AgentType.claude,
            state: tab.workspaceId == 'w-waiting'
                ? AgentStatusState.waiting
                : AgentStatusState.working,
            prompt: 'Prompt',
            updatedAt: _t0,
            stateStartedAt: _t0,
          );
        }
      }
      return statuses;
    }

    test('needs-you workspaces rank above working and idle in flat mode', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        workspaceSort: WorkbenchSortBy.activity,
      );
      final state = activityState(prefs);
      final rows = buildSidebarRows(
        state,
        agentStatuses: activityStatuses(state),
        now: _t0,
      );
      final ids = rows
          .whereType<WorkbenchWorkspaceRow>()
          .map((r) => r.workspace.id)
          .toList();
      expect(ids, <String>['w-waiting', 'w-working', 'w-idle']);
    });

    test('project headers rank by their most urgent workspace', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        projectSort: WorkbenchSortBy.activity,
      );
      final state = activityState(prefs);
      final rows = buildSidebarRows(
        state,
        agentStatuses: activityStatuses(state),
        now: _t0,
      );
      final headers = rows.whereType<WorkbenchProjectHeaderRow>().toList();
      expect(headers.first.project.id, 'p-alera');
    });

    test('the active workspace keeps its previous position', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        workspaceSort: WorkbenchSortBy.activity,
      );
      final state = activityState(prefs, activeWorkspaceId: 'w-working');
      final rows = buildSidebarRows(
        state,
        agentStatuses: activityStatuses(state),
        now: _t0,
        // Previous render had the active workspace first.
        previousWorkspaceOrder: <String>['w-working', 'w-waiting', 'w-idle'],
      );
      final ids = rows
          .whereType<WorkbenchWorkspaceRow>()
          .map((r) => r.workspace.id)
          .toList();
      expect(ids.first, 'w-working');
    });

    test('idle workspaces fall back to the persisted activity timestamp', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        workspaceSort: WorkbenchSortBy.activity,
      );
      final alera = _project('p-alera', 'alera');
      final a = _workspace('w-a', alera.id, 'aaa', 'a');
      final b = _workspace('w-b', alera.id, 'bbb', 'b');
      final state = WorkbenchState(
        projects: <Project>[alera],
        workspacesByProject: <String, List<Workspace>>{
          alera.id: <Workspace>[a, b],
        },
        viewPrefs: prefs,
        bootstrapped: true,
      );
      final rows = buildSidebarRows(
        state,
        lastActivityByWorkspaceId: <String, DateTime>{
          'w-b': _t0.add(const Duration(days: 1)),
        },
        now: _t0,
      );
      final ids = rows
          .whereType<WorkbenchWorkspaceRow>()
          .map((r) => r.workspace.id)
          .toList();
      expect(ids, <String>['w-b', 'w-a']);
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
