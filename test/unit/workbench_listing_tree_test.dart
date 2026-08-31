import 'package:alera/src/features/workbench/application/workbench_listing_tree.dart';
import 'package:alera/src/features/workbench/application/workspace_descendants.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _t0 = .utc(2026, 5, 1);

Workspace _workspace(String id, {String? parentId}) {
  return Workspace(
    id: id,
    projectId: 'p-1',
    name: id,
    branch: 'main',
    path: '/repo/$id',
    createdAt: _t0,
    updatedAt: _t0,
    kind: .linked,
    status: .active,
    parentWorkspaceId: parentId,
  );
}

void main() {
  test('children nest under their parent preserving sibling order', () {
    final entries = <Workspace>[
      _workspace('a'),
      _workspace('b', parentId: 'a'),
      _workspace('c', parentId: 'a'),
      _workspace('d'),
    ];

    final tree = buildWorkspaceTree(
      entries: entries,
      collapsedParentIds: const <String>{},
    );

    expect(tree.map((e) => e.workspace.id), <String>['a', 'b', 'c', 'd']);
    expect(tree.map((e) => e.depth), <int>[0, 1, 1, 0]);
    expect(tree.first.visibleChildCount, 2);
    expect(tree.first.hasVisibleChildren, isTrue);
    expect(tree.last.visibleChildCount, 0);
    expect(tree.last.hasVisibleChildren, isFalse);
  });

  test('a child whose parent is absent is promoted to root', () {
    final entries = <Workspace>[
      _workspace('orphan', parentId: 'filtered-out'),
      _workspace('root'),
    ];

    final tree = buildWorkspaceTree(
      entries: entries,
      collapsedParentIds: const <String>{},
    );

    expect(tree.map((e) => e.depth), everyElement(0));
    expect(tree.map((e) => e.workspace.id), <String>['orphan', 'root']);
  });

  test('collapsed parents hide their whole subtree', () {
    final entries = <Workspace>[
      _workspace('a'),
      _workspace('b', parentId: 'a'),
      _workspace('c', parentId: 'b'),
      _workspace('d'),
    ];

    final tree = buildWorkspaceTree(
      entries: entries,
      collapsedParentIds: const <String>{'a'},
    );

    expect(tree.map((e) => e.workspace.id), <String>['a', 'd']);
    expect(tree.first.childrenCollapsed, isTrue);
    // Count still reflects children even while they are hidden.
    expect(tree.first.visibleChildCount, 1);
  });

  test('nesting depth is capped for deep chains', () {
    final entries = <Workspace>[
      _workspace('w0'),
      for (var i = 1; i <= 6; i++) _workspace('w$i', parentId: 'w${i - 1}'),
    ];

    final tree = buildWorkspaceTree(
      entries: entries,
      collapsedParentIds: const <String>{},
    );

    expect(tree.last.depth, maxWorkspaceTreeDepth);
  });

  test('descendant ids walk the parent relation transitively', () {
    final workspaces = <Workspace>[
      _workspace('a'),
      _workspace('b', parentId: 'a'),
      _workspace('c', parentId: 'b'),
      _workspace('d'),
    ];

    expect(workspaceIdsDescendedFrom(workspaces, 'a'), <String>{'b', 'c'});
    expect(workspaceIdsDescendedFrom(workspaces, 'd'), isEmpty);
  });

  test('a parent cycle does not treat the root as its own descendant', () {
    final workspaces = <Workspace>[
      _workspace('a', parentId: 'b'),
      _workspace('b', parentId: 'a'),
    ];

    expect(workspaceIdsDescendedFrom(workspaces, 'a'), <String>{'b'});
    expect(workspaceIdsDescendedFrom(workspaces, 'b'), <String>{'a'});
  });

  test('a stale relation cycle terminates and keeps every workspace', () {
    final entries = <Workspace>[
      _workspace('a', parentId: 'b'),
      _workspace('b', parentId: 'a'),
      _workspace('root'),
    ];

    final tree = buildWorkspaceTree(
      entries: entries,
      collapsedParentIds: const <String>{},
    );

    expect(tree, hasLength(3));
    expect(tree.map((e) => e.workspace.id).toSet(), <String>{'a', 'b', 'root'});
  });
}
