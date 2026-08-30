import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _t0 = .utc(2026, 5, 1);

Project _project(String id, String name) {
  return Project(
    id: id,
    name: name,
    repoPath: '/repo/$id',
    createdAt: _t0,
    updatedAt: _t0,
  );
}

Workspace _workspace(
  String id,
  String projectId,
  String name, {
  WorkspaceKind kind = WorkspaceKind.linked,
  List<String> tagIds = const <String>[],
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: name,
    branch: name,
    path: '/repo/$projectId/$id',
    createdAt: _t0,
    updatedAt: _t0,
    kind: kind,
    status: .active,
    tagIds: tagIds,
  );
}

WorkbenchState _state(WorkbenchViewPrefs prefs, {String searchQuery = ''}) {
  final alera = _project('p-alera', 'alera');
  final orca = _project('p-orca', 'orca');
  return WorkbenchState(
    projects: <Project>[alera, orca],
    workspacesByProject: <String, List<Workspace>>{
      alera.id: <Workspace>[
        _workspace('w-alera-main', alera.id, 'main', kind: .main),
        _workspace(
          'w-alera-feature',
          alera.id,
          'feature',
          tagIds: <String>['t1'],
        ),
      ],
      orca.id: <Workspace>[
        _workspace('w-orca-main', orca.id, 'develop', kind: .main),
      ],
    },
    viewPrefs: prefs,
    activeProjectId: alera.id,
    searchQuery: searchQuery,
    bootstrapped: true,
  );
}

void main() {
  group('workspace kind filter', () {
    test('all shows every workspace', () {
      final state = _state(.defaults);
      final rows = buildSidebarRows(state);
      expect(
        workspaceOrderOfRows(rows),
        containsAll(<String>['w-alera-main', 'w-alera-feature', 'w-orca-main']),
      );
      expect(countVisibleWorkspaces(state), 3);
    });

    test('defaultOnly keeps only main worktrees', () {
      final state = _state(
        WorkbenchViewPrefs.defaults.copyWith(workspaceKindFilter: .defaultOnly),
      );
      final rows = buildSidebarRows(state);
      expect(
        workspaceOrderOfRows(rows),
        containsAll(<String>['w-alera-main', 'w-orca-main']),
      );
      expect(workspaceOrderOfRows(rows), isNot(contains('w-alera-feature')));
      expect(countVisibleWorkspaces(state), 2);
    });

    test(
      'nonDefaultOnly keeps only linked worktrees and hides empty projects',
      () {
        final state = _state(
          WorkbenchViewPrefs.defaults.copyWith(
            workspaceKindFilter: .nonDefaultOnly,
          ),
        );
        final rows = buildSidebarRows(state);
        expect(workspaceOrderOfRows(rows), <String>['w-alera-feature']);
        expect(countVisibleWorkspaces(state), 1);
        // orca has no linked workspaces, so its header disappears while the
        // filter is active.
        final headers = rows.whereType<WorkbenchProjectHeaderRow>().toList();
        expect(headers.any((row) => row.project.id == 'p-orca'), isFalse);
      },
    );

    test('combines with the tag filter and search query', () {
      final tagged = _state(
        WorkbenchViewPrefs.defaults.copyWith(
          workspaceKindFilter: .defaultOnly,
          selectedTagIds: <String>{'t1'},
        ),
      );
      // The only tagged workspace is linked, so both filters together match
      // nothing.
      expect(countVisibleWorkspaces(tagged), 0);

      final searched = _state(
        WorkbenchViewPrefs.defaults.copyWith(
          workspaceKindFilter: .nonDefaultOnly,
        ),
        searchQuery: 'develop',
      );
      // The search matches a default workspace, but the kind filter still
      // excludes it.
      expect(countVisibleWorkspaces(searched), 0);
    });

    test('collapse targets honor the kind filter', () {
      final state = _state(
        WorkbenchViewPrefs.defaults.copyWith(
          workspaceKindFilter: .nonDefaultOnly,
        ),
      );
      final targets = visibleSidebarCollapseTargets(state);
      expect(targets.workspaceIds, <String>{'w-alera-feature'});
      expect(targets.projectIds, <String>{'p-alera'});
    });
  });
}
