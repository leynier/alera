import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkbenchLayout', () {
    test(
      'sanitizes missing tabs and appends orphan tabs to the first group',
      () {
        final layout =
            WorkbenchLayout.single(
              workspaceId: 'workspace-1',
              tabIds: const <String>['missing-tab'],
            ).splitWithGroup(
              targetGroupId: WorkbenchLayout.defaultGroupId('workspace-1'),
              zone: WorkbenchDropZone.right,
              newGroup: WorkbenchPaneGroup(
                id: 'group-2',
                tabIds: const <String>['tab-2'],
                activeTabId: 'tab-2',
              ),
            );

        final sanitized = layout.sanitize(<WorkspaceTabRecord>[
          _tab('tab-1'),
          _tab('tab-2'),
        ]);

        expect(sanitized.paneGroupIds, <String>['group-2']);
        expect(sanitized.groups['group-2']?.tabIds, <String>['tab-2', 'tab-1']);
        expect(sanitized.activeTabId, 'tab-2');
      },
    );

    test('moves a tab into another stack without changing its id', () {
      final layout =
          WorkbenchLayout.single(
            workspaceId: 'workspace-1',
            tabIds: const <String>['tab-1', 'tab-2'],
          ).splitWithGroup(
            targetGroupId: WorkbenchLayout.defaultGroupId('workspace-1'),
            zone: WorkbenchDropZone.right,
            newGroup: WorkbenchPaneGroup(
              id: 'group-2',
              tabIds: const <String>['tab-3'],
              activeTabId: 'tab-3',
            ),
          );

      final moved = layout.moveTab(
        tabId: 'tab-2',
        targetGroupId: 'group-2',
        zone: WorkbenchDropZone.center,
        newGroupId: 'unused-group',
      );

      expect(
        moved.groups[WorkbenchLayout.defaultGroupId('workspace-1')]?.tabIds,
        <String>['tab-1'],
      );
      expect(moved.groups['group-2']?.tabIds, <String>['tab-3', 'tab-2']);
      expect(moved.activeTabId, 'tab-2');
    });

    test(
      'supports indexed insertion and ignores invalid active-tab targets',
      () {
        final groupId = WorkbenchLayout.defaultGroupId('workspace-1');
        final layout = WorkbenchLayout.single(
          workspaceId: 'workspace-1',
          tabIds: const <String>['tab-1'],
        );

        final inserted = layout.addTabToGroup(
          groupId: groupId,
          tabId: 'tab-2',
          index: 0,
        );

        expect(inserted.groups[groupId]?.tabIds, <String>['tab-2', 'tab-1']);
        expect(inserted.activeTabId, 'tab-2');
        expect(
          inserted.setActiveTab(groupId: 'missing', tabId: 'tab-2'),
          same(inserted),
        );
        expect(
          inserted.setActiveTab(groupId: groupId, tabId: 'tab-missing'),
          same(inserted),
        );
      },
    );

    test('creates directional splits and collapses an emptied group', () {
      final firstGroupId = WorkbenchLayout.defaultGroupId('workspace-1');
      final layout =
          WorkbenchLayout.single(
            workspaceId: 'workspace-1',
            tabIds: const <String>['tab-1', 'tab-2'],
          ).moveTab(
            tabId: 'tab-2',
            targetGroupId: firstGroupId,
            zone: WorkbenchDropZone.down,
            newGroupId: 'group-2',
          );

      expect(layout.paneGroupIds, <String>[firstGroupId, 'group-2']);
      expect(layout.root.axis, WorkbenchSplitAxis.vertical);

      final collapsed = layout.removeTab('tab-2');

      expect(collapsed.paneGroupIds, <String>[firstGroupId]);
      expect(collapsed.groups[firstGroupId]?.tabIds, <String>['tab-1']);
    });

    test(
      'sanitizes to a fresh single layout when every stored group is stale',
      () {
        final layout =
            WorkbenchLayout.single(
              workspaceId: 'workspace-1',
              tabIds: const <String>['missing-a'],
            ).splitWithGroup(
              targetGroupId: WorkbenchLayout.defaultGroupId('workspace-1'),
              zone: WorkbenchDropZone.right,
              newGroup: WorkbenchPaneGroup(
                id: 'group-2',
                tabIds: const <String>['missing-b'],
                activeTabId: 'missing-b',
              ),
            );

        final sanitized = layout.sanitize(<WorkspaceTabRecord>[_tab('tab-1')]);

        expect(sanitized.paneGroupIds, <String>[
          WorkbenchLayout.defaultGroupId('workspace-1'),
        ]);
        expect(
          sanitized
              .groups[WorkbenchLayout.defaultGroupId('workspace-1')]
              ?.tabIds,
          <String>['tab-1'],
        );
      },
    );

    test(
      'removeTab falls back to an empty single layout when no tabs remain',
      () {
        final layout = WorkbenchLayout.single(
          workspaceId: 'workspace-1',
          tabIds: const <String>['tab-1'],
        );

        final removed = layout.removeTab('tab-1');

        expect(removed.paneGroupIds, <String>[
          WorkbenchLayout.defaultGroupId('workspace-1'),
        ]);
        expect(
          removed.groups[WorkbenchLayout.defaultGroupId('workspace-1')]?.tabIds,
          isEmpty,
        );
        expect(removed.activeTabId, isNull);
      },
    );

    test(
      'removeTab falls back to the first tab when the active tab becomes stale',
      () {
        final groupId = WorkbenchLayout.defaultGroupId('workspace-1');
        final layout = WorkbenchLayout(
          workspaceId: 'workspace-1',
          root: WorkbenchLayoutNode.leaf(groupId),
          groups: <String, WorkbenchPaneGroup>{
            groupId: WorkbenchPaneGroup(
              id: groupId,
              tabIds: const <String>['tab-1', 'tab-2'],
              activeTabId: 'missing-tab',
            ),
          },
          activeGroupId: groupId,
        );

        final removed = layout.removeTab('tab-2');

        expect(removed.groups[groupId]?.tabIds, <String>['tab-1']);
        expect(removed.activeTabId, 'tab-1');
      },
    );

    test('merges a nested group into its immediate sibling', () {
      final firstGroupId = WorkbenchLayout.defaultGroupId('workspace-1');
      final layout =
          WorkbenchLayout.single(
                workspaceId: 'workspace-1',
                tabIds: const <String>['tab-a'],
              )
              .splitWithGroup(
                targetGroupId: firstGroupId,
                zone: WorkbenchDropZone.right,
                newGroup: WorkbenchPaneGroup(
                  id: 'group-c',
                  tabIds: const <String>['tab-c'],
                  activeTabId: 'tab-c',
                ),
              )
              .splitWithGroup(
                targetGroupId: firstGroupId,
                zone: WorkbenchDropZone.right,
                newGroup: WorkbenchPaneGroup(
                  id: 'group-b',
                  tabIds: const <String>['tab-b'],
                  activeTabId: 'tab-b',
                ),
              );

      final merged = layout.mergeGroupIntoSibling('group-b');

      expect(merged.paneGroupIds, <String>[firstGroupId, 'group-c']);
      expect(merged.groups[firstGroupId]?.tabIds, <String>['tab-a', 'tab-b']);
      expect(merged.groups['group-b'], isNull);
      expect(merged.groups['group-c']?.tabIds, <String>['tab-c']);
      expect(merged.activeGroupId, firstGroupId);
    });

    test('split, move, and merge ignore invalid no-op operations', () {
      final groupId = WorkbenchLayout.defaultGroupId('workspace-1');
      final layout = WorkbenchLayout.single(
        workspaceId: 'workspace-1',
        tabIds: const <String>['tab-1'],
      );

      expect(
        layout.splitWithGroup(
          targetGroupId: groupId,
          zone: WorkbenchDropZone.center,
          newGroup: WorkbenchPaneGroup(
            id: 'group-2',
            tabIds: const <String>['tab-2'],
            activeTabId: 'tab-2',
          ),
        ),
        same(layout),
      );
      expect(
        layout.splitWithGroup(
          targetGroupId: 'missing',
          zone: WorkbenchDropZone.right,
          newGroup: WorkbenchPaneGroup(
            id: 'group-2',
            tabIds: const <String>['tab-2'],
            activeTabId: 'tab-2',
          ),
        ),
        same(layout),
      );
      expect(
        layout.moveTab(
          tabId: 'missing',
          targetGroupId: groupId,
          zone: WorkbenchDropZone.center,
          newGroupId: 'group-2',
        ),
        same(layout),
      );
      expect(
        layout.moveTab(
          tabId: 'tab-1',
          targetGroupId: groupId,
          zone: WorkbenchDropZone.right,
          newGroupId: 'group-2',
        ),
        same(layout),
      );
      expect(layout.mergeGroupIntoSibling('missing'), same(layout));
      expect(layout.mergeGroupIntoSibling(groupId), same(layout));
    });

    test('persists split ratios with clamping', () {
      final layout =
          WorkbenchLayout.single(
            workspaceId: 'workspace-1',
            tabIds: const <String>['tab-1'],
          ).splitWithGroup(
            targetGroupId: WorkbenchLayout.defaultGroupId('workspace-1'),
            zone: WorkbenchDropZone.right,
            newGroup: WorkbenchPaneGroup(
              id: 'group-2',
              tabIds: const <String>['tab-2'],
              activeTabId: 'tab-2',
            ),
          );

      final narrow = layout.updateSplitRatio(const <int>[], 0.02);
      final wide = layout.updateSplitRatio(const <int>[], 0.98);

      expect(narrow.root.ratio, workbenchMinSplitRatio);
      expect(wide.root.ratio, workbenchMaxSplitRatio);
    });

    test('updates nested split ratios without changing parent ratios', () {
      final rootGroupId = WorkbenchLayout.defaultGroupId('workspace-1');
      final nested =
          WorkbenchLayout.single(
                workspaceId: 'workspace-1',
                tabIds: const <String>['tab-1'],
              )
              .splitWithGroup(
                targetGroupId: rootGroupId,
                zone: WorkbenchDropZone.right,
                newGroup: WorkbenchPaneGroup(
                  id: 'group-2',
                  tabIds: const <String>['tab-2'],
                  activeTabId: 'tab-2',
                ),
              )
              .splitWithGroup(
                targetGroupId: rootGroupId,
                zone: WorkbenchDropZone.down,
                newGroup: WorkbenchPaneGroup(
                  id: 'group-3',
                  tabIds: const <String>['tab-3'],
                  activeTabId: 'tab-3',
                ),
              );

      final updated = nested.updateSplitRatio(const <int>[0], 0.02);

      expect(updated.root.ratio, nested.root.ratio);
      expect(updated.root.first?.ratio, workbenchMinSplitRatio);
    });

    test(
      'sanitize falls back to a single layout when the stored root is stale',
      () {
        final layout = WorkbenchLayout(
          workspaceId: 'workspace-1',
          root: WorkbenchLayoutNode.leaf('missing-group'),
          groups: <String, WorkbenchPaneGroup>{
            'group-a': WorkbenchPaneGroup(
              id: 'group-a',
              tabIds: const <String>['tab-a'],
              activeTabId: 'tab-a',
            ),
          },
          activeGroupId: 'group-a',
        );

        final sanitized = layout.sanitize(<WorkspaceTabRecord>[
          _tab('tab-a'),
          _tab('tab-b'),
        ]);

        expect(sanitized.paneGroupIds, <String>[
          WorkbenchLayout.defaultGroupId('workspace-1'),
        ]);
        expect(
          sanitized
              .groups[WorkbenchLayout.defaultGroupId('workspace-1')]
              ?.tabIds,
          <String>['tab-a', 'tab-b'],
        );
      },
    );

    test(
      'removeTab falls back to a single layout when the remaining root is stale',
      () {
        final layout = WorkbenchLayout(
          workspaceId: 'workspace-1',
          root: WorkbenchLayoutNode.leaf('missing-group'),
          groups: <String, WorkbenchPaneGroup>{
            'group-a': WorkbenchPaneGroup(
              id: 'group-a',
              tabIds: const <String>['tab-a', 'tab-b'],
              activeTabId: 'tab-b',
            ),
          },
          activeGroupId: 'group-a',
        );

        final removed = layout.removeTab('tab-a');

        expect(removed.paneGroupIds, <String>[
          WorkbenchLayout.defaultGroupId('workspace-1'),
        ]);
        expect(
          removed.groups[WorkbenchLayout.defaultGroupId('workspace-1')]?.tabIds,
          <String>['tab-b'],
        );
      },
    );

    test(
      'moveTab falls back to the active group when the target is missing',
      () {
        final groupId = WorkbenchLayout.defaultGroupId('workspace-1');
        final layout = WorkbenchLayout.single(
          workspaceId: 'workspace-1',
          tabIds: const <String>['tab-1', 'tab-2'],
        );

        final centered = layout.moveTab(
          tabId: 'tab-2',
          targetGroupId: 'missing-group',
          zone: WorkbenchDropZone.center,
          newGroupId: 'unused',
          index: 0,
        );
        final split = layout.moveTab(
          tabId: 'tab-2',
          targetGroupId: 'missing-group',
          zone: WorkbenchDropZone.left,
          newGroupId: 'group-2',
        );

        expect(centered.groups[groupId]?.tabIds, <String>['tab-2', 'tab-1']);
        expect(split.paneGroupIds, <String>['group-2', groupId]);
        expect(split.root.axis, WorkbenchSplitAxis.horizontal);
      },
    );

    test('merges first and nested-second groups into their siblings', () {
      final rootGroupId = WorkbenchLayout.defaultGroupId('workspace-1');
      final layout =
          WorkbenchLayout.single(
                workspaceId: 'workspace-1',
                tabIds: const <String>['tab-a'],
              )
              .splitWithGroup(
                targetGroupId: rootGroupId,
                zone: WorkbenchDropZone.right,
                newGroup: WorkbenchPaneGroup(
                  id: 'group-b',
                  tabIds: const <String>['tab-b'],
                  activeTabId: 'tab-b',
                ),
              )
              .splitWithGroup(
                targetGroupId: 'group-b',
                zone: WorkbenchDropZone.down,
                newGroup: WorkbenchPaneGroup(
                  id: 'group-c',
                  tabIds: const <String>['tab-c'],
                  activeTabId: 'tab-c',
                ),
              );

      final mergedRoot = layout.mergeGroupIntoSibling(rootGroupId);
      final mergedNested = layout.mergeGroupIntoSibling('group-c');

      expect(mergedRoot.groups['group-b']?.tabIds, <String>['tab-b', 'tab-a']);
      expect(mergedNested.groups['group-b']?.tabIds, <String>[
        'tab-b',
        'tab-c',
      ]);
    });
  });
}

WorkspaceTabRecord _tab(String id) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: 'workspace-1',
    title: id,
    createdAt: DateTime.utc(2026, 5, 22),
    updatedAt: DateTime.utc(2026, 5, 22),
  );
}
