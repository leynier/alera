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

  testWidgets('shows the browser start surface for browser tabs', (
    tester,
  ) async {
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

    expect(find.text('Start Browsing'), findsOneWidget);
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
    // Only the rendered tab gets a session at all. The inactive tab used to
    // appear here with visibility false because the tab strip built a handle,
    // and its xterm buffer, for every chip.
    expect(terminalRuntime.visibilityByTab, <String, bool>{'tab-1': true});

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
    expect(
      terminalRuntime.requestedTabIds,
      <String>['tab-1', 'tab-2'],
      reason: 'a handle is created only when a tab is actually rendered',
    );
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
    await tester.tap(find.text('Split Right'));
    await tester.pumpAndSettle();

    expect(splitGroups, <_SplitGroupAction>[
      const _SplitGroupAction('group-a', WorkbenchDropZone.right),
    ]);

    await tester.tap(find.byTooltip('Pane actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Split'));
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

    for (final label in <String>['Split Down', 'Split Left', 'Split Up']) {
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

  testWidgets('new tab callbacks and selection include the group id', (
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
    final createdBrowserTabs = <String?>[];
    final createdCodexTabs = <String?>[];

    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: layout,
      createdTabs: createdTabs,
      createdBrowserTabs: createdBrowserTabs,
      createdCodexTabs: createdCodexTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
    );

    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Terminal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Browser Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    final codexIcon = find.byKey(const ValueKey<String>('new-tab-codex-icon'));
    expect(codexIcon, findsOneWidget);
    expect(
      tester.widget<AgentIdentityIcon>(codexIcon).agentType,
      AgentType.codex,
    );
    expect(
      find.ancestor(of: codexIcon, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    await tester.tap(find.text('New Codex Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminal 1'));
    await tester.pump();

    expect(createdTabs, <String?>['group-a']);
    expect(createdBrowserTabs, <String?>['group-a']);
    expect(createdCodexTabs, <String?>['group-a']);
    expect(selectedTabs, <_SelectedTabAction>[
      const _SelectedTabAction('group-a', 'tab-1'),
    ]);
    expect(terminalRuntime.focusRequestsByTab['tab-1'], 1);
  });

  testWidgets('Codex tabs use the Codex identity icon', (tester) async {
    final codexTab = _tab(
      'codex-tab',
      title: 'Generated title',
      kind: WorkspaceTabKind.codex,
    );
    await _pumpWorkbenchView(
      tester,
      tabs: <WorkspaceTabRecord>[codexTab],
      terminalRuntime: terminalRuntime,
      layout: WorkbenchLayout.single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: <String>[codexTab.id],
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

    expect(find.text('Generated title'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workspace-tab-codex-icon-codex-tab')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(
          const ValueKey<String>('workspace-tab-codex-icon-codex-tab'),
        ),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });
}
