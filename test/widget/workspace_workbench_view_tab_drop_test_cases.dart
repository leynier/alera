part of 'workspace_workbench_view_test.dart';

void _registerWorkspaceWorkbenchViewTabDropTests() {
  // Drag grab point within the chip. DragTarget details.offset is the
  // feedback origin (pointer minus grab point), so horizontal drop aims
  // below compensate with grabDelta.dx while the pointer itself must stay
  // inside the hovered chip for hit testing.
  const grabDelta = Offset(4, 16);

  Finder draggableTabs() =>
      find.byWidgetPredicate((widget) => widget is Draggable);

  Future<TestGesture> startTabDrag(WidgetTester tester, int chipIndex) async {
    final gesture = await tester.startGesture(
      tester.getTopLeft(draggableTabs().at(chipIndex)) + grabDelta,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 100));
    return gesture;
  }

  Future<void> dropAt(
    WidgetTester tester,
    TestGesture gesture,
    Offset target,
  ) async {
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dropping on the right half of a chip reorders the tab', (
    tester,
  ) async {
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
      size: const Size(620, 320),
    );

    final gesture = await startTabDrag(tester, 0);
    final lastChipRect = tester.getRect(draggableTabs().at(2));
    await dropAt(
      tester,
      gesture,
      Offset(lastChipRect.right - 2, lastChipRect.center.dy),
    );

    expect(movedTabs, <_MovedTabAction>[
      const _MovedTabAction(
        'tab-1',
        'group-a',
        WorkbenchDropZone.center,
        index: 2,
      ),
    ]);
  });

  testWidgets('dropping on the left half of a chip inserts before it', (
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

    final gesture = await startTabDrag(tester, 1);
    final firstChipRect = tester.getRect(draggableTabs().at(0));
    await dropAt(
      tester,
      gesture,
      Offset(firstChipRect.left + grabDelta.dx + 2, firstChipRect.center.dy),
    );

    expect(movedTabs, <_MovedTabAction>[
      const _MovedTabAction(
        'tab-2',
        'group-a',
        WorkbenchDropZone.center,
        index: 0,
      ),
    ]);
  });

  testWidgets('dropping on the empty strip area appends at the end', (
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

    final gesture = await startTabDrag(tester, 1);
    final firstChipRect = tester.getRect(draggableTabs().at(0));
    final leftPaneRect = tester.getRect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
    );
    await dropAt(
      tester,
      gesture,
      Offset(
        (firstChipRect.right + leftPaneRect.right) / 2,
        firstChipRect.center.dy,
      ),
    );

    expect(movedTabs, <_MovedTabAction>[
      const _MovedTabAction(
        'tab-2',
        'group-a',
        WorkbenchDropZone.center,
        index: 1,
      ),
    ]);
  });

  testWidgets('dropping a tab on its own position is a no-op', (tester) async {
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
      size: const Size(620, 320),
    );

    final gesture = await startTabDrag(tester, 0);
    final firstChipRect = tester.getRect(draggableTabs().at(0));
    await dropAt(
      tester,
      gesture,
      Offset(firstChipRect.left + grabDelta.dx + 2, firstChipRect.center.dy),
    );

    expect(movedTabs, isEmpty);
  });

  testWidgets('shows the insertion indicator only while hovering the strip', (
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
      size: const Size(620, 320),
    );

    const indicator = ValueKey<String>('tab-strip-insertion-indicator');
    final gesture = await startTabDrag(tester, 0);
    final secondChipRect = tester.getRect(draggableTabs().at(1));

    await gesture.moveTo(
      Offset(secondChipRect.right - 2, secondChipRect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(indicator), findsOneWidget);

    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey<String>('terminal-tab-2'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(indicator), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
