part of 'alera_shell_page_test.dart';

void _registerAleraShellWorkspaceRemovalTests() {
  testWidgets('linked workspace removal closes runtime and removes the row', (
    tester,
  ) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Keep or Delete Branch?'), findsOneWidget);
    expect(harness.runtime.closedWorkspaceIds, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep Branch'));
    await tester.pumpAndSettle();
    expect(find.textContaining('All tabs will close'), findsOneWidget);
    expect(harness.runtime.closedWorkspaceIds, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Clean Up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.runtime.closedWorkspaceIds, <String>['workspace-2']);
    expect(
      harness.controller.state.workspacesFor('project-1').map((w) => w.id),
      <String>['workspace-1'],
    );
    expect(find.text('Feature login'), findsNothing);
  });

  testWidgets('cancelling workspace removal leaves its tabs and runtime open', (
    tester,
  ) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );
    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(harness.runtime.closedWorkspaceIds, isEmpty);
    expect(
      harness.controller.state
          .workspacesFor('project-1')
          .map((workspace) => workspace.id),
      contains('workspace-2'),
    );
    expect(harness.controller.state.tabsFor('workspace-2'), isNotEmpty);
  });

  testWidgets('workspace removal dialog omits branch details when blank', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState(linkedExpanded: true);
    final workspaces = seeded.workspacesFor('project-1');
    final branchlessState = seeded.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        'project-1': <Workspace>[
          workspaces.first,
          workspaces.last.copyWith(branch: ''),
        ],
      },
    );

    await _pumpShell(tester, state: branchlessState);

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The workspace branch is unknown'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Delete Branch'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Keep Branch'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This removes the worktree for "Feature login".'),
      findsOneWidget,
    );
    expect(find.textContaining('deletes branch'), findsNothing);
  });

  testWidgets('workspace removal failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await _pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        deleteWorkspaceFailure: StateError('delete workspace failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Keep Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clean Up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: delete workspace failed');
  });
}
