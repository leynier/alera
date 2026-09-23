part of 'workspace_workbench_view_test.dart';

void _registerWorkspaceWorkbenchViewPaneFocusTests() {
  testWidgets('switching tabs keeps focus in its own pane across columns', (
    tester,
  ) async {
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Left 1'),
      _tab('tab-2', title: 'Left 2'),
      _tab('tab-3', title: 'Right'),
    ];
    final activatedGroups = <String>[];

    WorkbenchLayout layoutWithLeftActive(String activeTabId) {
      return WorkbenchLayout(
        workspaceId: _workspaceId,
        root: .split(
          axis: .horizontal,
          first: .leaf('group-a'),
          second: .leaf('group-b'),
          ratio: 0.5,
        ),
        groups: <String, WorkbenchPaneGroup>{
          'group-a': WorkbenchPaneGroup(
            id: 'group-a',
            tabIds: <String>['tab-1', 'tab-2'],
            activeTabId: activeTabId,
          ),
          'group-b': WorkbenchPaneGroup(
            id: 'group-b',
            tabIds: <String>['tab-3'],
            activeTabId: 'tab-3',
          ),
        },
        activeGroupId: 'group-a',
      );
    }

    Future<void> pump(String activeLeftTabId) {
      return _pumpWorkbenchView(
        tester,
        tabs: tabs,
        terminalRuntime: terminalRuntime,
        layout: layoutWithLeftActive(activeLeftTabId),
        createdTabs: createdTabs,
        selectedTabs: selectedTabs,
        closedTabs: closedTabs,
        closedTabGroups: closedTabGroups,
        renamedTabs: renamedTabs,
        movedTabs: movedTabs,
        splitGroups: splitGroups,
        mergedGroups: mergedGroups,
        updatedRatios: updatedRatios,
        activatedGroups: activatedGroups,
        size: const Size(620, 320),
      );
    }

    await pump('tab-1');
    await tester.pump();
    // The user worked in the right column at some point, then came back to
    // the left one, so the right terminal sits in the focus history.
    terminalRuntime._sessions['tab-3']!.focusNode.requestFocus();
    await tester.pump();
    terminalRuntime._sessions['tab-1']!.focusNode.requestFocus();
    await tester.pump();
    expect(terminalRuntime._sessions['tab-1']!.focusNode.hasFocus, isTrue);
    activatedGroups.clear();

    // Ctrl+Tab in the left column: the controller activates Left 2 and the
    // pane rebuilds with that terminal.
    await pump('tab-2');
    await tester.pump();

    expect(terminalRuntime._sessions['tab-2']!.focusNode.hasFocus, isTrue);
    expect(terminalRuntime._sessions['tab-3']!.focusNode.hasFocus, isFalse);
    expect(
      activatedGroups,
      isNot(contains('group-b')),
      reason: 'focus released by the old tab must not promote the other pane',
    );
  });
}
