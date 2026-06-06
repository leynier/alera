part of 'workspace_workbench_view_test.dart';

void _registerWorkspaceWorkbenchViewTabTests() {
  testWidgets('tab context menu closes sibling tabs', (tester) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
      _tab('tab-3', title: 'Terminal 3'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout.single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: tabs.map((tab) => tab.id).toList(),
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

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Close others'));
    await tester.pumpAndSettle();

    expect(closedTabGroups, <List<String>>[
      <String>['tab-1', 'tab-3'],
    ]);

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Close tabs to the right'));
    await tester.pumpAndSettle();

    expect(closedTabGroups, <List<String>>[
      <String>['tab-1', 'tab-3'],
      <String>['tab-3'],
    ]);
  });

  testWidgets('tab context menu renames and splits the active group', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout.single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: tabs.map((tab) => tab.id).toList(),
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

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Change title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Renamed terminal');
    await tester.tap(find.text('Change title').last);
    await tester.pumpAndSettle();

    expect(renamedTabs, <String>['Renamed terminal']);

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(
      splitGroups,
      contains(const _SplitGroupAction('group-a', WorkbenchDropZone.right)),
    );
  });

  testWidgets('tab context menu routes split up, down, left, and close', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout.single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: tabs.map((tab) => tab.id).toList(),
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

    for (final label in <String>['Split up', 'Split down', 'Split left']) {
      await _openTabContextMenu(tester, 'Terminal 2');
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await _openTabContextMenu(tester, 'Terminal 2');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(
      splitGroups,
      containsAll(<_SplitGroupAction>[
        const _SplitGroupAction('group-a', WorkbenchDropZone.up),
        const _SplitGroupAction('group-a', WorkbenchDropZone.down),
        const _SplitGroupAction('group-a', WorkbenchDropZone.left),
      ]),
    );
    expect(closedTabs, <String>['tab-2']);
  });

  testWidgets('active-tab fallback picks the first available tab', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: WorkbenchLayoutNode.leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: tabs.map((tab) => tab.id).toList(),
            activeTabId: 'missing-tab',
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

    expect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
      findsOneWidget,
    );
    expect(terminalRuntime.requestedTabIds, contains('tab-1'));
  });

  testWidgets('terminal tab chips show agent status dots', (tester) async {
    final tab = _tab('tab-1', title: 'Terminal');

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[tab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout.single(
        workspaceId: _workspaceId,
        tabIds: <String>[tab.id],
      ),
      agentStatuses: <String, AgentStatusEntry>{
        tab.terminalSessionId: _agentStatus(
          tab,
          state: AgentStatusState.waiting,
        ),
      },
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

    expect(find.byType(AgentStatusDot), findsOneWidget);
  });

  testWidgets('browser tabs use the browser icon in the chip', (tester) async {
    final tab = _tab('tab-1', title: 'Browser', kind: WorkspaceTabKind.browser);

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[tab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout.single(
        workspaceId: _workspaceId,
        tabIds: <String>[tab.id],
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

    expect(find.byIcon(Icons.public), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('editor tabs use file icons in the chip', (tester) async {
    final terminalTab = _tab('tab-1', title: 'Terminal');
    final editorTab = _tab(
      'tab-2',
      title: 'main.dart',
      kind: WorkspaceTabKind.editor,
      filePath: 'lib/main.dart',
    );

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, editorTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout(
        workspaceId: _workspaceId,
        root: WorkbenchLayoutNode.leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[terminalTab.id, editorTab.id],
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

    final icon = tester.widget<AleraFileIcon>(find.byType(AleraFileIcon));
    expect(icon.kind, AleraFileIconKind.file);
    expect(icon.pathOrName, 'lib/main.dart');
  });
}
