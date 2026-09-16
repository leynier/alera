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

    expect(harness.runtime.totalFocusRequests, 1);
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

    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.tab);
    await tester.sendKeyUpEvent(.tab);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.layoutFor('workspace-1')!.activeTabId,
      'tab-1',
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

    expect(harness.runtime.totalFocusRequests, 1);
  });
}
