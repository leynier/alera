import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace_transfer_layout.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceTabRecord tab(String id, String workspace) => WorkspaceTabRecord(
  id: id,
  workspaceId: workspace,
  kind: .terminal,
  title: id,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('round trip retains colliding split groups and active selection', () {
    final source = WorkbenchLayout(
      workspaceId: 'child',
      root: WorkbenchLayoutNode.split(
        axis: .vertical,
        first: .leaf('main/main'),
        second: .leaf('other'),
        ratio: 0.3,
      ),
      groups: {
        'main/main': WorkbenchPaneGroup(
          id: 'main/main',
          tabIds: ['agent'],
          activeTabId: 'agent',
        ),
        'other': WorkbenchPaneGroup(
          id: 'other',
          tabIds: ['notes'],
          activeTabId: 'notes',
        ),
      },
      activeGroupId: 'other',
    );
    final merged = mergeWorkspaceTransferLayout(
      sourceId: 'child',
      destinationId: 'main',
      source: source,
      destination: WorkbenchLayout.single(
        workspaceId: 'main',
        tabIds: ['editor'],
      ),
      sourceTabs: [tab('agent', 'child'), tab('notes', 'child')],
      destinationTabs: [tab('editor', 'main')],
    );
    expect(merged.root.leafGroupIds().toSet().length, 3);
    expect(merged.groups['main/main']!.tabIds, ['editor']);
    expect(merged.groups['main/main/handoff/1']!.tabIds, ['agent']);
    expect(merged.activeTabId, 'notes');
    expect(merged.root.first!.ratio, 0.3);
  });

  test('missing source layout and already streamed tabs are deduplicated', () {
    final merged = mergeWorkspaceTransferLayout(
      sourceId: 'child',
      destinationId: 'main',
      sourceTabs: [tab('agent', 'child')],
      destinationTabs: [tab('editor', 'main'), tab('agent', 'main')],
    );
    final ids = merged.groups.values.expand((group) => group.tabIds).toList();
    expect(ids.toSet(), {'agent', 'editor'});
    expect(ids.length, 2);
  });
}
