part of 'workspace_workbench_view_test.dart';

void _registerWorkspaceWorkbenchViewPaneTests() {
  testWidgets('falls back to a single layout when none is provided', (
    tester,
  ) async {
    final tab = _tab('tab-1', title: 'Terminal 1');

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[tab],
      terminalRuntime: terminalRuntime,
      layout: null,
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

    expect(find.text('Terminal 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
      findsOneWidget,
    );
    expect(terminalRuntime.requestedTabIds, contains('tab-1'));
  });

  testWidgets('shows a loading state for non-terminal tabs', (tester) async {
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

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(terminalRuntime.requestedTabIds, isEmpty);
  });

  testWidgets('non-terminal tab title taps select without terminal focus', (
    tester,
  ) async {
    final terminalTab = _tab('tab-1', title: 'Terminal 1');
    final editorTab = _tab(
      'tab-2',
      title: 'Browser',
      kind: WorkspaceTabKind.browser,
    );

    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[terminalTab, editorTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout.single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: <String>[editorTab.id, terminalTab.id],
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

    await tester.tap(find.text('Browser'));
    await tester.pump();

    expect(selectedTabs, <_SelectedTabAction>[
      const _SelectedTabAction('group-a', 'tab-2'),
    ]);
    expect(terminalRuntime.focusRequestsByTab['tab-1'], 0);
  });

  testWidgets('marks only the active terminal tab visible', (tester) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    WorkbenchLayout layoutWithActive(String activeTabId) {
      return WorkbenchLayout(
        workspaceId: _workspaceId,
        root: WorkbenchLayoutNode.leaf('group-a'),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>[for (final tab in tabs) tab.id],
            activeTabId: activeTabId,
          ),
        },
        activeGroupId: 'group-a',
      );
    }

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: layoutWithActive('tab-1'),
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
    expect(terminalRuntime.visibilityByTab, <String, bool>{
      'tab-1': true,
      'tab-2': false,
    });

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: layoutWithActive('tab-2'),
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

    expect(terminalRuntime.visibilityByTab, <String, bool>{
      'tab-1': false,
      'tab-2': true,
    });
  });

  testWidgets('dragging the split handle updates the split ratio', (
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
      layout: _splitLayout(
        firstTabId: tabs[0].id,
        secondTabId: tabs[1].id,
        axis: WorkbenchSplitAxis.vertical,
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

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(WorkspaceWorkbenchView)),
    );
    await gesture.moveBy(const Offset(48, 0));
    await gesture.up();
    await tester.pump();

    expect(updatedRatios, hasLength(1));
    expect(updatedRatios.single.nodePath, const <int>[]);
    expect(updatedRatios.single.ratio, isA<double>());
  });

  testWidgets('split handles track hover and cancelled drags', (tester) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
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

    final handlePoint = tester.getCenter(find.byType(WorkspaceWorkbenchView));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: handlePoint);
    await tester.pump();
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();

    final drag = await tester.startGesture(handlePoint);
    await tester.pump();
    await drag.cancel();
    await tester.pump();

    expect(updatedRatios, isEmpty);
  });

  testWidgets('dragging a tab across panes invokes the move callback', (
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
      layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
      size: const Size(620, 320),
    );

    final draggableTabs = find.byWidgetPredicate(
      (widget) => widget is Draggable,
    );
    final dragStart =
        tester.getTopLeft(draggableTabs.at(1)) + const Offset(24, 16);
    final leftPaneRect = tester.getRect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
    );

    final gesture = await tester.startGesture(dragStart);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(Offset(leftPaneRect.left + 8, leftPaneRect.center.dy));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      movedTabs,
      contains(
        const _MovedTabAction('tab-2', 'group-a', WorkbenchDropZone.left),
      ),
    );
  });

  testWidgets('pane actions forward split and merge callbacks', (tester) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
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

    await tester.tap(find.byTooltip('Pane actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(splitGroups, <_SplitGroupAction>[
      const _SplitGroupAction('group-a', WorkbenchDropZone.right),
    ]);

    await tester.tap(find.byTooltip('Pane actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close split'));
    await tester.pumpAndSettle();

    expect(mergedGroups, <String>['group-a']);
  });

  testWidgets('pane actions route split down, left, and up', (tester) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: _splitLayout(firstTabId: tabs[0].id, secondTabId: tabs[1].id),
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

    for (final label in <String>['Split down', 'Split left', 'Split up']) {
      await tester.tap(find.byTooltip('Pane actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(splitGroups, <_SplitGroupAction>[
      const _SplitGroupAction('group-a', WorkbenchDropZone.down),
      const _SplitGroupAction('group-a', WorkbenchDropZone.left),
      const _SplitGroupAction('group-a', WorkbenchDropZone.up),
    ]);
  });

  testWidgets('new terminal and tab selection callbacks include the group id', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab('tab-2', title: 'Terminal 2'),
    ];
    final layout = WorkbenchLayout.single(
      workspaceId: _workspaceId,
      groupId: 'group-a',
      tabIds: tabs.map((tab) => tab.id).toList(),
    );

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: layout,
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

    await tester.tap(find.byTooltip('New terminal'));
    await tester.pump();
    await tester.tap(find.text('Terminal 1'));
    await tester.pump();

    expect(createdTabs, <String?>['group-a']);
    expect(selectedTabs, <_SelectedTabAction>[
      const _SelectedTabAction('group-a', 'tab-1'),
    ]);
    expect(terminalRuntime.focusRequestsByTab['tab-1'], 1);
  });
}
