import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30);
Workspace _workspace(
  String id,
  String project, {
  String? section,
  String? parent,
  bool pinned = false,
}) => Workspace(
  id: id,
  projectId: project,
  name: id,
  path: '/$id',
  createdAt: _now,
  updatedAt: _now,
  kind: WorkspaceKind.linked,
  status: WorkspaceStatus.active,
  sectionId: section,
  parentWorkspaceId: parent,
  isPinned: pinned,
);
WorkbenchState _state() => WorkbenchState(
  projects: [
    for (final id in ['p', 'q'])
      Project(
        id: id,
        name: id,
        repoPath: '/$id',
        createdAt: _now,
        updatedAt: _now,
      ),
  ],
  sections: [
    WorkspaceSection(id: 'a', name: 'Alpha', createdAt: _now, updatedAt: _now),
    WorkspaceSection(
      id: 'z',
      name: 'Zulu',
      createdAt: _now,
      updatedAt: _now.add(const Duration(days: 1)),
    ),
  ],
  workspacesByProject: {
    'p': [
      _workspace('parent', 'p', section: 'a'),
      _workspace('unassigned', 'p'),
      _workspace('pinned', 'p', section: 'z', pinned: true),
    ],
    'q': [
      _workspace('same', 'q', section: 'a', parent: 'parent'),
      _workspace('different', 'q', section: 'z', parent: 'parent'),
    ],
  },
  viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
    groupBy: WorkbenchGroupBy.section,
  ),
);

void main() {
  test(
    'collapse targets include visible pinned copies independently of sections',
    () {
      final initial = _state();
      for (final repeat in [false, true]) {
        final state = initial.copyWith(
          viewPrefs: initial.viewPrefs.copyWith(
            showPinnedWorkspacesBelow: repeat,
            collapsedSectionIds: {'z'},
            expandedWorkspaceIds: {'pinned'},
          ),
        );
        final targets = visibleSidebarCollapseTargets(state);
        expect(targets.workspaceIds, contains('pinned'));
        expect(targets.isCollapsed(state.viewPrefs), isFalse);
        final hidden = state.copyWith(
          viewPrefs: state.viewPrefs.copyWith(pinnedSectionCollapsed: true),
        );
        expect(
          visibleSidebarCollapseTargets(hidden).workspaceIds,
          isNot(contains('pinned')),
        );
        final filtered = state.copyWith(searchQuery: 'parent');
        expect(
          visibleSidebarCollapseTargets(filtered).workspaceIds,
          isNot(contains('pinned')),
        );
      }
    },
  );

  test(
    'all-pinned section view has collapse targets without custom headers',
    () {
      final initial = _state();
      final state = initial.copyWith(
        workspacesByProject: {
          'p': [_workspace('pinned', 'p', section: 'z', pinned: true)],
        },
        viewPrefs: initial.viewPrefs.copyWith(
          showPinnedWorkspacesBelow: false,
          expandedWorkspaceIds: {'pinned'},
        ),
      );
      final targets = visibleSidebarCollapseTargets(state);
      expect(targets.isEmpty, isFalse);
      expect(targets.workspaceIds, {'pinned'});
      expect(targets.sectionIds, isEmpty);
      expect(targets.hasOthers, isFalse);
    },
  );

  test('section activity uses member workspaces and keeps Others last', () {
    final state = _state();
    final withTabs = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        sectionSort: WorkbenchSortBy.activity,
      ),
      tabsByWorkspace: {
        for (final id in ['parent', 'different'])
          id: [
            WorkspaceTabRecord(
              id: 'tab-$id',
              workspaceId: id,
              kind: WorkspaceTabKind.terminal,
              title: 'Terminal',
              createdAt: _now,
              updatedAt: _now,
            ),
          ],
      },
    );
    final rows = buildSidebarRows(
      withTabs,
      lastActivityByWorkspaceId: {
        'parent': _now,
        'different': _now.add(const Duration(minutes: 1)),
      },
    );
    expect(
      rows.whereType<WorkbenchSectionHeaderRow>().map((row) => row.label),
      ['Zulu', 'Alpha', 'Others'],
    );
  });

  test(
    'sections mix projects, keep Others last and nest only within a section',
    () {
      final rows = buildSidebarRows(_state());
      expect(
        rows.whereType<WorkbenchSectionHeaderRow>().map((row) => row.label),
        ['Alpha', 'Zulu', 'Others'],
      );
      final workspaces = rows
          .whereType<WorkbenchWorkspaceRow>()
          .where((row) => !row.isPinnedCopy)
          .toList();
      expect(
        workspaces.singleWhere((row) => row.workspace.id == 'same').indent,
        2,
      );
      expect(
        workspaces.singleWhere((row) => row.workspace.id == 'different').indent,
        1,
      );
      expect(workspaces.every((row) => row.showProjectChip), isTrue);
      expect(workspaces.map((row) => row.workspace.id).toSet().length, 5);
    },
  );
  test('sort, filters, section search and collapse preserve memberships', () {
    final state = _state();
    final recent = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(sectionSort: WorkbenchSortBy.recent),
    );
    expect(
      buildSidebarRows(recent)
          .whereType<WorkbenchSectionHeaderRow>()
          .map((row) => row.label),
      ['Zulu', 'Alpha', 'Others'],
    );
    final searched = state.copyWith(searchQuery: 'Alpha');
    expect(countVisibleWorkspaces(searched), 2);
    expect(
      buildSidebarRows(searched)
          .whereType<WorkbenchSectionHeaderRow>()
          .map((row) => row.label),
      ['Alpha'],
    );
    final collapsed = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        collapsedSectionIds: {'a'},
        othersSectionCollapsed: true,
        showPinnedWorkspacesBelow: false,
      ),
    );
    final rows = buildSidebarRows(collapsed);
    expect(
      rows
          .whereType<WorkbenchWorkspaceRow>()
          .where((row) => !row.isPinnedCopy)
          .map((row) => row.workspace.id),
      ['different'],
    );
    expect(visibleSidebarCollapseTargets(collapsed).sectionIds, {'a', 'z'});
    expect(state.workspacesFor('p').first.sectionId, 'a');
  });
  test('new preferences roundtrip and old preferences keep defaults', () {
    final prefs = _state().viewPrefs.copyWith(
      sectionSort: WorkbenchSortBy.recent,
      collapsedSectionIds: {'a'},
      othersSectionCollapsed: true,
    );
    expect(WorkbenchViewPrefs.fromJson(prefs.toMap()), prefs);
    final old = WorkbenchViewPrefs.defaults.toMap()
      ..remove('sectionSort')
      ..remove('collapsedSectionIds')
      ..remove('othersSectionCollapsed');
    expect(WorkbenchViewPrefs.fromJson(old).sectionSort, WorkbenchSortBy.name);
  });
}
