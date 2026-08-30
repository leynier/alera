import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkbenchLayout serialization', () {
    test('serializes and restores a split layout', () {
      final layout =
          WorkbenchLayout.single(
            workspaceId: 'workspace-1',
            tabIds: const <String>['tab-1'],
          ).splitWithGroup(
            targetGroupId: WorkbenchLayout.defaultGroupId('workspace-1'),
            zone: .right,
            newGroup: WorkbenchPaneGroup(
              id: 'group-2',
              tabIds: const <String>['tab-2'],
              activeTabId: 'tab-2',
            ),
          );

      final restored = WorkbenchLayout.fromJson(
        Map<String, Object?>.from(layout.toMap()),
      );

      expect(restored.workspaceId, 'workspace-1');
      expect(restored.paneGroupIds, <String>[
        WorkbenchLayout.defaultGroupId('workspace-1'),
        'group-2',
      ]);
      expect(restored.groups['group-2']?.tabIds, <String>['tab-2']);
    });

    test('validates identifiers and restores groups and nodes from json', () {
      expect(
        () => WorkbenchPaneGroup(
          id: '',
          tabIds: const <String>['tab-1'],
          activeTabId: 'tab-1',
        ),
        throwsArgumentError,
      );
      expect(() => WorkbenchLayoutNode.leaf(''), throwsArgumentError);

      final group = WorkbenchPaneGroup.fromJson(<String, Object?>{
        'id': 'group-a',
        'tabIds': <String>['tab-1'],
        'activeTabId': 'tab-1',
      });
      final leaf = WorkbenchLayoutNode.fromJson(<String, Object?>{
        'type': 'leaf',
        'groupId': 'group-a',
      });
      final split = WorkbenchLayoutNode.fromJson(<String, Object?>{
        'type': 'split',
        'axis': 'horizontal',
        'ratio': 0.4,
        'first': <String, Object?>{'type': 'leaf', 'groupId': 'group-a'},
        'second': <String, Object?>{'type': 'leaf', 'groupId': 'group-b'},
      });

      expect(group.id, 'group-a');
      expect(group.tabIds, <String>['tab-1']);
      expect(leaf.groupId, 'group-a');
      expect(leaf.axis, isNull);
      expect(leaf.ratio, isNull);
      expect(split.groupId, isNull);
      expect(split.axis, WorkbenchSplitAxis.horizontal);

      expect(
        () => WorkbenchLayout(
          workspaceId: '',
          root: .leaf('group-a'),
          groups: <String, WorkbenchPaneGroup>{'group-a': group},
          activeGroupId: 'group-a',
        ),
        throwsArgumentError,
      );
      expect(
        () => WorkbenchLayout(
          workspaceId: 'workspace-1',
          root: .leaf('group-a'),
          groups: <String, WorkbenchPaneGroup>{'group-a': group},
          activeGroupId: '',
        ),
        throwsArgumentError,
      );
    });
  });
}
