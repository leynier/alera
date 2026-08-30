part of 'workspace_workbench_view_test.dart';

void _registerWorkspaceWorkbenchViewPreviewTabTests() {
  testWidgets('preview file tabs render italic titles', (tester) async {
    final terminalTab = _tab('tab-1', title: 'Terminal');
    final previewTab = _tab(
      'tab-2',
      title: 'main.dart',
      kind: .editor,
      filePath: 'lib/main.dart',
      preview: true,
    );

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, previewTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[terminalTab.id, previewTab.id],
            activeTabId: terminalTab.id,
          ),
        },
        activeGroupId: 'group-a',
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
      keptPreviewTabs: <String>[],
    );

    final title = tester.widget<Text>(find.text('main.dart'));
    expect(title.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('preview tab context menu offers Keep Open', (tester) async {
    final terminalTab = _tab('tab-1', title: 'Terminal');
    final previewTab = _tab(
      'tab-2',
      title: 'main.dart',
      kind: .editor,
      filePath: 'lib/main.dart',
      preview: true,
    );
    final keptPreviewTabs = <String>[];

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, previewTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[terminalTab.id, previewTab.id],
            activeTabId: terminalTab.id,
          ),
        },
        activeGroupId: 'group-a',
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
      keptPreviewTabs: keptPreviewTabs,
    );

    await _openTabContextMenu(tester, 'main.dart');
    expect(find.text('Keep Open'), findsOneWidget);
    await tester.tap(find.text('Keep Open'));
    await tester.pumpAndSettle();
    expect(keptPreviewTabs, <String>[previewTab.id]);
  });

  testWidgets('Keep Open is hidden when preview keep is unavailable', (
    tester,
  ) async {
    final previewTab = _tab(
      'tab-1',
      title: 'main.dart',
      kind: .editor,
      filePath: 'lib/main.dart',
      preview: true,
    );
    final terminalTab = _tab('tab-2', title: 'Terminal');

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, previewTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[terminalTab.id, previewTab.id],
            activeTabId: terminalTab.id,
          ),
        },
        activeGroupId: 'group-a',
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    await _openTabContextMenu(tester, 'main.dart');
    expect(find.text('Keep Open'), findsNothing);
  });

  testWidgets('double activating a preview tab keeps it open', (tester) async {
    final previewTab = _tab('tab-1', title: 'Terminal', preview: true);
    final keptPreviewTabs = <String>[];

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[previewTab],
      terminalRuntime: terminalRuntime,
      layout: .single(
        workspaceId: _workspaceId,
        tabIds: <String>[previewTab.id],
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
      keptPreviewTabs: keptPreviewTabs,
    );

    await tester.tap(find.text('Terminal'));
    await tester.pump();
    await tester.tap(find.text('Terminal'));
    await tester.pump();

    expect(keptPreviewTabs, <String>[previewTab.id]);
  });
}
