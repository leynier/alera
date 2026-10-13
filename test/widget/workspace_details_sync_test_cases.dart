part of 'workspace_details_overlay_test.dart';

WorkspaceDetailsState _withRepository(GitRepositoryState repository) =>
    WorkspaceDetailsState(
      sourceControl: WorkspaceSourceControlState(
        status: const GitStatusResult(entries: []),
        repositoryState: repository,
        stashes: const [],
      ),
      comparison: details.comparison,
      branches: details.branches,
      defaultBranch: details.defaultBranch,
      quickAction: details.quickAction,
      pullRequest: null,
      hasRemote: true,
    );

void _registerWorkspaceDetailsSyncTests() {
  testWidgets('the branch row shows commits ahead and behind upstream', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(
      tester,
      const Size(1000, 800),
      loadDetails: () async => _withRepository(
        const GitRepositoryState(
          branch: 'feature/details',
          upstream: 'origin/feature/details',
          ahead: 2,
          behind: 1,
        ),
      ),
    );
    expect(find.byIcon(AleraIcons.arrowUp), findsOneWidget);
    expect(find.byIcon(AleraIcons.arrowDown), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Unpublished'), findsNothing);
  });

  testWidgets('an unpublished branch says so and the menu fetches', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _fetches = 0;
    await pumpOverlay(tester, const Size(1000, 800));
    expect(find.text('Unpublished'), findsOneWidget);
    await tester.tap(find.byTooltip('feature/details Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();
    expect(_fetches, 1);
  });
}
