part of 'workspace_git_diff_panel_test.dart';

void _registerWorkspaceGitDiffPanelBranchTests() {
  testWidgets('source control branch control opens the switcher', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..sourceBranches = <String>['main', 'feature']
      ..gitRepositoryStateResult = const GitRepositoryState(branch: 'main');

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Switch Branch'), findsOneWidget);
    await tester.tap(find.byTooltip('Switch Branch'));
    await tester.pumpAndSettle();

    expect(find.text('Switch Branch'), findsWidgets);
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('Create Branch'), findsOneWidget);
  });

  testWidgets('switching a branch from source control checks it out', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..sourceBranches = <String>['main', 'feature']
      ..gitRepositoryStateResult = const GitRepositoryState(branch: 'main');

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Switch Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature'));
    await tester.pumpAndSettle();

    expect(
      backend.calls
          .where((call) => call.method == 'checkoutBranch')
          .single
          .args,
      <String, Object?>{'path': '/tmp/project', 'branch': 'feature'},
    );
    expect(find.byTooltip('Switch Branch'), findsOneWidget);
    expect(find.text('feature'), findsWidgets);
  });

  testWidgets('creating a branch from source control checks it out', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(branch: 'main');

    await _pumpPanel(tester, backend: backend);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Switch Branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Branch'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'ship/login');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(
      backend.calls
          .where((call) => call.method == 'createAndCheckoutBranch')
          .single
          .args,
      <String, Object?>{'path': '/tmp/project', 'branch': 'ship/login'},
    );
    expect(find.text('ship/login'), findsWidgets);
  });
}
