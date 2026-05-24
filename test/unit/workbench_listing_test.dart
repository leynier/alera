import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
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
  );
}

TerminalTabRecord _tab(String id, String workspaceId, String title) {
  return TerminalTabRecord(
    id: id,
    workspaceId: workspaceId,
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
  final resolvedPrefs = prefs ??
      WorkbenchViewPrefs.defaults.copyWith(
        // Default behaviour mirrors the controller: activating a workspace
        // also expands it so its terminals are visible.
        expandedWorkspaceIds: <String>{
          ?activeWorkspaceId,
        },
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
    tabsByWorkspace: <String, List<TerminalTabRecord>>{
      aleraMain.id: <TerminalTabRecord>[
        _tab('t-1', aleraMain.id, 'Terminal 1'),
        _tab('t-2', aleraMain.id, 'Terminal 2'),
      ],
    },
    viewPrefs: resolvedPrefs,
    activeProjectId: alera.id,
    activeWorkspaceId: activeWorkspaceId,
    searchQuery: searchQuery,
    bootstrapped: true,
  );
}

void main() {
  group('buildSidebarRows · group by project', () {
    test('emits project headers, workspace rows and terminal rows', () {
      final rows = buildSidebarRows(_fixtureState());
      // alera header → Main + 2 terminals + feature, orca header → Main
      expect(rows, hasLength(7));
      expect(rows[0], isA<WorkbenchProjectHeaderRow>());
      expect((rows[0] as WorkbenchProjectHeaderRow).project.name, 'alera');
      expect(rows[1], isA<WorkbenchWorkspaceRow>());
      expect((rows[1] as WorkbenchWorkspaceRow).workspace.name, 'Main');
      expect((rows[1] as WorkbenchWorkspaceRow).showProjectChip, isFalse);
      expect(rows[2], isA<WorkbenchTerminalRow>());
      expect(rows[3], isA<WorkbenchTerminalRow>());
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

    test('terminals appear when the workspace is in the expansion set', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        expandedWorkspaceIds: <String>{'w-alera-main'},
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      expect(rows.whereType<WorkbenchTerminalRow>(), hasLength(2));
    });

    test('workspace without an expansion entry shows no terminals', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        // expandedWorkspaceIds is empty — no workspace should reveal its
        // terminals even though one is active in the state fixture.
      );
      final rows = buildSidebarRows(_fixtureState(prefs: prefs));
      expect(rows.whereType<WorkbenchTerminalRow>(), isEmpty);
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
      final rows = buildSidebarRows(
        _fixtureState(searchQuery: 'feature'),
      );
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
      expect(
        countVisibleWorkspaces(_fixtureState(searchQuery: 'feature')),
        1,
      );
    });
  });
}
