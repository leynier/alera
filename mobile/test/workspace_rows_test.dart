import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildWorkspaceTree', () {
    test('Orders children depth-first under their parents', () {
      final tree = buildWorkspaceTree(
        entries: <WorkspaceSummary>[
          _workspace('root'),
          _workspace('child-a', parent: 'root'),
          _workspace('grandchild', parent: 'child-a'),
          _workspace('child-b', parent: 'root'),
        ],
        collapsedParentIds: const <String>{},
      );

      expect(tree.map((entry) => entry.workspace.id).toList(), <String>[
        'root',
        'child-a',
        'grandchild',
        'child-b',
      ]);
      expect(tree[0].depth, 0);
      expect(tree[1].depth, 1);
      expect(tree[2].depth, 2);
      expect(tree[0].visibleChildCount, 2);
    });

    test('Collapsing a parent hides its subtree but keeps the count', () {
      final tree = buildWorkspaceTree(
        entries: <WorkspaceSummary>[
          _workspace('root'),
          _workspace('child-a', parent: 'root'),
          _workspace('grandchild', parent: 'child-a'),
        ],
        collapsedParentIds: const <String>{'root'},
      );

      expect(tree.map((entry) => entry.workspace.id).toList(), <String>[
        'root',
      ]);
      expect(tree.single.childrenCollapsed, isTrue);
      expect(tree.single.visibleChildCount, 1);
    });

    test('Promotes orphans and cycles to the root level', () {
      final tree = buildWorkspaceTree(
        entries: <WorkspaceSummary>[
          _workspace('orphan', parent: 'missing'),
          _workspace('cycle-a', parent: 'cycle-b'),
          _workspace('cycle-b', parent: 'cycle-a'),
        ],
        collapsedParentIds: const <String>{},
      );

      expect(tree, hasLength(3));
      expect(tree.first.workspace.id, 'orphan');
      expect(tree.first.depth, 0);
    });

    test('Caps indentation at the max tree depth', () {
      final entries = <WorkspaceSummary>[_workspace('w0')];
      for (var i = 1; i < 8; i++) {
        entries.add(_workspace('w$i', parent: 'w${i - 1}'));
      }
      final tree = buildWorkspaceTree(
        entries: entries,
        collapsedParentIds: const <String>{},
      );

      expect(tree.last.depth, maxWorkspaceTreeDepth);
    });

    test('Computes descendants transitively', () {
      final workspaces = <WorkspaceSummary>[
        _workspace('root'),
        _workspace('child', parent: 'root'),
        _workspace('grandchild', parent: 'child'),
        _workspace('other'),
      ];

      expect(workspaceDescendantIds(workspaces, 'root'), <String>{
        'child',
        'grandchild',
      });
      expect(workspaceDescendantIds(workspaces, 'other'), isEmpty);
    });
  });

  group('buildMobileWorkspaceRows', () {
    test('Renders the pinned section first with flat copies', () {
      final rows = buildMobileWorkspaceRows(
        workspaces: <WorkspaceSummary>[
          _workspace('a', project: 'p1'),
          _workspace('b', project: 'p1', pinned: true),
        ],
        projects: <ProjectSummary>[_project('p1')],
        prefs: const MobileViewPrefs(groupBy: MobileWorkspaceGroupBy.none),
      );

      expect(rows.first, isA<MobilePinnedHeaderRow>());
      final pinnedCopy = rows[1] as MobileWorkspaceEntryRow;
      expect(pinnedCopy.isPinnedCopy, isTrue);
      expect(pinnedCopy.entry.workspace.id, 'b');
      final treeIds = rows
          .skip(2)
          .whereType<MobileWorkspaceEntryRow>()
          .map((row) => row.entry.workspace.id)
          .toList();
      expect(treeIds, <String>['a', 'b']);
    });

    test('Collapsed pinned section hides copies but keeps the header', () {
      final rows = buildMobileWorkspaceRows(
        workspaces: <WorkspaceSummary>[
          _workspace('b', project: 'p1', pinned: true),
        ],
        projects: <ProjectSummary>[_project('p1')],
        prefs: const MobileViewPrefs(
          groupBy: MobileWorkspaceGroupBy.none,
          pinnedSectionCollapsed: true,
        ),
      );

      expect(rows.first, isA<MobilePinnedHeaderRow>());
      expect((rows.first as MobilePinnedHeaderRow).collapsed, isTrue);
      final copies = rows.whereType<MobileWorkspaceEntryRow>().where(
        (row) => row.isPinnedCopy,
      );
      expect(copies, isEmpty);
    });

    test('Groups by project in project order with collapse', () {
      final rows = buildMobileWorkspaceRows(
        workspaces: <WorkspaceSummary>[
          _workspace('w2', project: 'p2'),
          _workspace('w1', project: 'p1'),
          _workspace('w1-child', project: 'p1', parent: 'w1'),
        ],
        projects: <ProjectSummary>[_project('p1'), _project('p2')],
        prefs: const MobileViewPrefs(collapsedProjectIds: <String>{'p2'}),
      );

      final headers = rows.whereType<MobileProjectHeaderRow>().toList();
      expect(headers.map((header) => header.projectId).toList(), <String>[
        'p1',
        'p2',
      ]);
      expect(headers.last.collapsed, isTrue);
      final entryIds = rows
          .whereType<MobileWorkspaceEntryRow>()
          .map((row) => row.entry.workspace.id)
          .toList();
      expect(entryIds, <String>['w1', 'w1-child']);
    });
  });
}

WorkspaceSummary _workspace(
  String id, {
  String project = 'p1',
  String? parent,
  bool pinned = false,
}) {
  return WorkspaceSummary(
    id: id,
    projectId: project,
    name: id,
    path: '/tmp/$id',
    branch: 'branch/$id',
    isPinned: pinned,
    parentWorkspaceId: parent,
  );
}

ProjectSummary _project(String id) {
  return ProjectSummary(id: id, name: 'Project $id', repoPath: '/repo/$id');
}
