import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkbenchLayout', () {
    test('serializes and restores a split layout', () {
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

      final restored = WorkbenchLayout.fromJson(layout.toJson());

      expect(restored.workspaceId, 'workspace-1');
      expect(restored.paneGroupIds, <String>[
        WorkbenchLayout.defaultGroupId('workspace-1'),
        'group-2',
      ]);
      expect(restored.groups['group-2']?.tabIds, <String>['tab-2']);
    });

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
