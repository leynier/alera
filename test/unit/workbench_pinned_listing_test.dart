import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 7, 16);

Project _project(String id) {
  return Project(
    id: id,
    name: id,
    repoPath: '/repo/$id',
    createdAt: _now,
    updatedAt: _now,
  );
}

Workspace _workspace(
  String id,
  String projectId, {
  required String name,
  bool isPinned = false,
  String? parentWorkspaceId,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: name,
    branch: 'feature/$id',
    path: '/repo/$projectId/$id',
    createdAt: _now,
    updatedAt: _now,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
    isPinned: isPinned,
    parentWorkspaceId: parentWorkspaceId,
  );
}

WorkbenchState _state({
  WorkbenchViewPrefs prefs = WorkbenchViewPrefs.defaults,
  String searchQuery = '',
  bool pinFeature = true,
}) {
  final alera = _project('alera');
  final orca = _project('orca');
  return WorkbenchState(
    projects: <Project>[alera, orca],
    workspacesByProject: <String, List<Workspace>>{
      alera.id: <Workspace>[
        _workspace('main', alera.id, name: 'Main'),
        _workspace('feature', alera.id, name: 'Feature', isPinned: pinFeature),
      ],
      orca.id: <Workspace>[_workspace('review', orca.id, name: 'Review')],
    },
    viewPrefs: prefs,
    searchQuery: searchQuery,
  );
}

void main() {
  test('adds a global duplicate without polluting regular order memory', () {
    final state = _state();
    final rows = buildSidebarRows(state);
    final copies = rows
        .whereType<WorkbenchWorkspaceRow>()
        .where((row) => row.workspace.id == 'feature')
        .toList();

    expect((rows.first as WorkbenchPinnedHeaderRow).workspaceCount, 1);
    expect(copies, hasLength(2));
    expect(copies.where((row) => row.isPinnedCopy), hasLength(1));
    expect(
      copies.firstWhere((row) => row.isPinnedCopy).showProjectChip,
      isTrue,
    );
    expect(
      workspaceOrderOfRows(rows).where((id) => id == 'feature'),
      hasLength(1),
    );
    expect(countVisibleWorkspaces(state), 3);
  });

  test('respects filters but ignores project collapse', () {
    final prefs = WorkbenchViewPrefs.defaults.copyWith(
      collapsedProjectIds: <String>{'alera'},
      selectedProjectIds: <String>{'alera'},
    );
    final visibleRows = buildSidebarRows(_state(prefs: prefs));
    final filteredRows = buildSidebarRows(
      _state(prefs: prefs, searchQuery: 'does-not-match'),
    );

    expect(
      visibleRows.whereType<WorkbenchWorkspaceRow>().where(
        (row) => row.isPinnedCopy,
      ),
      hasLength(1),
    );
    expect(filteredRows.whereType<WorkbenchPinnedHeaderRow>(), isEmpty);
  });

  test('builds a tree from pinned workspaces only', () {
    final project = _project('alera');
    final parent = _workspace(
      'parent',
      project.id,
      name: 'Parent',
      isPinned: true,
    );
    final child = _workspace(
      'child',
      project.id,
      name: 'Child',
      isPinned: true,
      parentWorkspaceId: parent.id,
    );
    final unpinnedParent = _workspace(
      'other-parent',
      project.id,
      name: 'Other Parent',
    );
    final orphanedPin = _workspace(
      'orphaned-pin',
      project.id,
      name: 'Orphaned Pin',
      isPinned: true,
      parentWorkspaceId: unpinnedParent.id,
    );
    final state = WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[parent, child, unpinnedParent, orphanedPin],
      },
    );

    final pinned = buildSidebarRows(state)
        .whereType<WorkbenchWorkspaceRow>()
        .where((row) => row.isPinnedCopy)
        .toList();

    expect(pinned.firstWhere((row) => row.workspace.id == parent.id).indent, 0);
    expect(pinned.firstWhere((row) => row.workspace.id == child.id).indent, 1);
    expect(
      pinned.firstWhere((row) => row.workspace.id == orphanedPin.id).indent,
      0,
    );
  });

  group('collapsible sections', () {
    test(
      'group by none adds a collapsible all section after the pinned copies',
      () {
        final prefs = WorkbenchViewPrefs.defaults.copyWith(
          groupBy: WorkbenchGroupBy.none,
        );
        final rows = buildSidebarRows(_state(prefs: prefs));

        final pinnedHeader = rows.first as WorkbenchPinnedHeaderRow;
        expect(pinnedHeader.workspaceCount, 1);
        expect(pinnedHeader.collapsed, isFalse);

        final allHeader = rows.whereType<WorkbenchAllHeaderRow>().single;
        expect(allHeader.workspaceCount, 3);
        expect(allHeader.collapsed, isFalse);

        final pinnedIndex = rows.indexOf(pinnedHeader);
        final allIndex = rows.indexOf(allHeader);
        final copies = rows
            .sublist(pinnedIndex + 1, allIndex)
            .whereType<WorkbenchWorkspaceRow>()
            .toList();
        expect(copies, hasLength(1));
        expect(copies.single.isPinnedCopy, isTrue);

        final regular = rows
            .sublist(allIndex + 1)
            .whereType<WorkbenchWorkspaceRow>()
            .toList();
        expect(regular, hasLength(3));
        expect(regular.every((row) => !row.isPinnedCopy), isTrue);
      },
    );

    test('collapsed pinned section keeps the headers and drops the copies', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        pinnedSectionCollapsed: true,
      );
      final rows = buildSidebarRows(_state(prefs: prefs));

      expect(
        rows.whereType<WorkbenchPinnedHeaderRow>().single.collapsed,
        isTrue,
      );
      expect(rows.whereType<WorkbenchAllHeaderRow>(), hasLength(1));
      final workspaces = rows.whereType<WorkbenchWorkspaceRow>().toList();
      expect(workspaces, hasLength(3));
      expect(workspaces.every((row) => !row.isPinnedCopy), isTrue);
    });

    test(
      'collapsed all section keeps pinned copies and drops the flat list',
      () {
        final prefs = WorkbenchViewPrefs.defaults.copyWith(
          groupBy: WorkbenchGroupBy.none,
          allSectionCollapsed: true,
        );
        final rows = buildSidebarRows(_state(prefs: prefs));

        expect(
          rows.whereType<WorkbenchAllHeaderRow>().single.collapsed,
          isTrue,
        );
        final workspaces = rows.whereType<WorkbenchWorkspaceRow>().toList();
        expect(workspaces, hasLength(1));
        expect(workspaces.single.isPinnedCopy, isTrue);
      },
    );

    test(
      'group by project has no all section but still collapses pinned copies',
      () {
        final prefs = WorkbenchViewPrefs.defaults.copyWith(
          pinnedSectionCollapsed: true,
        );
        final rows = buildSidebarRows(_state(prefs: prefs));

        expect(rows.whereType<WorkbenchAllHeaderRow>(), isEmpty);
        expect(
          rows.whereType<WorkbenchPinnedHeaderRow>().single.collapsed,
          isTrue,
        );
        expect(
          rows.whereType<WorkbenchWorkspaceRow>().any(
            (row) => row.isPinnedCopy,
          ),
          isFalse,
        );
      },
    );

    test('flat list without pinned workspaces has no section headers', () {
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
      );
      final rows = buildSidebarRows(_state(prefs: prefs, pinFeature: false));

      expect(rows.whereType<WorkbenchPinnedHeaderRow>(), isEmpty);
      expect(rows.whereType<WorkbenchAllHeaderRow>(), isEmpty);
      expect(rows.whereType<WorkbenchWorkspaceRow>(), hasLength(3));
    });
  });
}
