part of 'alera_shell_page_test.dart';

void _registerAleraShellWorkspaceFocusTests() {
  testWidgets(
    'a runtime focus request leaves the Board and shows the workspace',
    (tester) async {
      final requests = StreamController<String>();
      addTearDown(requests.close);
      final window = _ShellFocusWindow();
      final harness = await _pumpShell(
        tester,
        state: _linkedWorkbenchState(),
        workspaceFocusRequests: requests.stream,
        windowActivator: window,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AleraShellPage)),
      );
      container.read(runBoardNavigationProvider.notifier).open();
      await tester.pump();
      expect(harness.controller.state.activeWorkspaceId, 'workspace-1');
      expect(_workbenchFor('workspace-2'), findsNothing);

      requests.add('workspace-2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(window.calls, 1);
      expect(container.read(runBoardNavigationProvider).visible, isFalse);
      expect(harness.controller.state.activeWorkspaceId, 'workspace-2');
      expect(
        harness.controller.state.tabsFor('workspace-2').map((tab) => tab.id),
        <String>['tab-2'],
      );
      expect(_workbenchFor('workspace-2'), findsOneWidget);
    },
  );

  testWidgets('an unknown workspace leaves the selection and window alone', (
    tester,
  ) async {
    final requests = StreamController<String>();
    addTearDown(requests.close);
    final window = _ShellFocusWindow();
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(),
      workspaceFocusRequests: requests.stream,
      windowActivator: window,
    );

    requests.add('missing-workspace');
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));

    expect(window.calls, 0);
    expect(harness.controller.state.activeWorkspaceId, 'workspace-1');
  });
}

Finder _workbenchFor(String workspaceId) => find.byWidgetPredicate(
  (widget) =>
      widget is WorkspaceWorkbenchView && widget.workspace.id == workspaceId,
);

class _ShellFocusWindow implements AgentNotificationWindowActivator {
  int calls = 0;

  @override
  Future<void> showAndFocus() async => calls++;
}
