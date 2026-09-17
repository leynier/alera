part of 'alera_shell_page_test.dart';

void _registerAleraShellShortcutTests() {
  testWidgets('new-terminal shortcut focuses the new session', (tester) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    // Focus a descendant so key events bubble up to the global scope.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.keyT);
    await tester.sendKeyUpEvent(.keyT);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, greaterThan(0));
  });

  testWidgets('close-tab shortcut closes the focused source control diff', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+  next();')],
            added: 1,
            removed: 0,
          ),
        ],
      );
    final harness = await _pumpShell(
      tester,
      state: _diffTabWorkbenchState(),
      gitBackend: backend,
    );
    await tester.pumpAndSettle();
    expect(find.text('+  next();'), findsOneWidget);
    await tester.tap(find.text('+  next();'));
    await tester.pumpAndSettle();

    // Nothing was clicked: the diff replaced the terminal as the active tab
    // and holds focus only because it claims it for the active pane.
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.keyW);
    await tester.sendKeyUpEvent(.keyW);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    final remaining = harness.controller.state.tabsFor('workspace-1');
    expect(remaining.map((tab) => tab.id), <String>['tab-1']);
    expect(find.text('+  next();'), findsNothing);
  });

  testWidgets('next-tab shortcut cycles from a focused source control diff', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitDiffResult = const GitDiffResult(
        files: <GitDiffFile>[
          GitDiffFile(
            path: 'lib/main.dart',
            area: .unstaged,
            status: .modified,
            lines: <GitDiffLine>[GitDiffLine.addition('+  next();')],
            added: 1,
            removed: 0,
          ),
        ],
      );
    final harness = await _pumpShell(
      tester,
      state: _diffTabWorkbenchState(),
      gitBackend: backend,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+  next();'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.tab);
    await tester.sendKeyUpEvent(.tab);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.workspacePanelFor('workspace-1').focusedKey,
      WorkspacePanel.tabKey('tab-1'),
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
  });

  testWidgets('split shortcut focuses the new pane terminal', (tester) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // Ctrl+Shift+D is the split-right default off macOS.
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.shiftLeft);
    await tester.sendKeyDownEvent(.keyD);
    await tester.sendKeyUpEvent(.keyD);
    await tester.sendKeyUpEvent(.shiftLeft);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, greaterThan(0));
  });

  testWidgets('pane focus and next-tab shortcuts stay in the chosen column', (
    tester,
  ) async {
    final base = _splitWorkbenchState();
    final workspace = base.activeWorkspace!;
    final now = DateTime.utc(2026, 5, 22);
    final thirdTab = WorkspaceTabRecord(
      id: 'tab-3',
      workspaceId: workspace.id,
      title: 'Terminal 3',
      createdAt: now,
      updatedAt: now,
    );
    final leftGroupId = WorkbenchLayout.defaultGroupId(workspace.id);
    final layout =
        WorkbenchLayout.single(
              workspaceId: workspace.id,
              tabIds: <String>['tab-1', thirdTab.id],
            )
            .setActiveTab(groupId: leftGroupId, tabId: 'tab-1')
            .splitWithGroup(
              targetGroupId: leftGroupId,
              zone: .right,
              newGroup: WorkbenchPaneGroup(
                id: 'group-2',
                tabIds: <String>['tab-2'],
                activeTabId: 'tab-2',
              ),
            );
    final harness = await _pumpShell(
      tester,
      state: base.copyWith(
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[
            ...base.tabsFor(workspace.id),
            thirdTab,
          ],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: layout},
        viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
          workspacePanels: <String, WorkspacePanel>{
            workspace.id: const WorkspacePanel()
                .applyMainLayout(_panelKeyedLayout(layout))
                .select(WorkspacePanel.tabKey('tab-2')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rightTerminal = find.byKey(
      const ValueKey<String>('fake-terminal-tab-2'),
    );
    expect(rightTerminal, findsOneWidget);
    Focus.of(tester.element(rightTerminal)).requestFocus();
    await tester.pumpAndSettle();
    // The right column is active and its terminal holds the focus.
    expect(harness.runtime.terminalHasFocus('tab-2'), isTrue);

    // Ctrl+Alt+Left is the focus-previous-pane default off macOS.
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.altLeft);
    await tester.sendKeyDownEvent(.arrowLeft);
    await tester.sendKeyUpEvent(.arrowLeft);
    await tester.sendKeyUpEvent(.altLeft);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    var current = harness.controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id);
    expect(current.activeGroupId, leftGroupId);
    expect(harness.runtime.terminalHasFocus('tab-1'), isTrue);
    expect(harness.runtime.terminalHasFocus('tab-2'), isFalse);

    // Ctrl+Tab cycles inside the focused column, and the focus follows the
    // newly active tab rather than jumping to the other column.
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.tab);
    await tester.sendKeyUpEvent(.tab);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    current = harness.controller.state
        .workspacePanelFor(workspace.id)
        .ensuredMainLayout(workspace.id);
    expect(current.activeGroupId, leftGroupId);
    expect(
      current.groups[leftGroupId]!.activeTabId,
      WorkspacePanel.tabKey(thirdTab.id),
    );
    expect(harness.runtime.terminalHasFocus('tab-3'), isTrue);
    expect(harness.runtime.terminalHasFocus('tab-2'), isFalse);
  });
}
