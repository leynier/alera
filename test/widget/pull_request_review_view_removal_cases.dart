part of 'pull_request_review_view_test.dart';

void _registerPullRequestReviewViewRemovalTests() {
  testWidgets('defaults a merged PR to Archive Workspace', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .merged)),
    );

    expect(find.text('Create Merge Commit'), findsNothing);
    expect(find.text('Close Pull Request'), findsNothing);
    expect(find.text('Archive Workspace'), findsOneWidget);
    expect(find.text('Remove Workspace'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsNothing);
    final archiveButton = tester.widget<Material>(
      find.byKey(
        const ValueKey<String>('pull-request-action-button-archiveWorkspace'),
      ),
    );
    expect(archiveButton.color, AleraTokens.accent);

    await tester.tap(find.text('Archive Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Archive Workspace?'), findsNothing);
    expect(callbacks.archiveWorkspaceCalls, 1);
    expect(callbacks.removeWorkspaceCalls, 0);
    expect(callbacks.unlinkCalls, 0);

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.text('Archive Workspace'), findsWidgets);
    expect(find.text('Remove Workspace'), findsOneWidget);
  });

  testWidgets('keeps unlink as the only merged action without archiving', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(
        callbacks,
        review: _review.copyWith(state: .merged),
        offerArchiveWorkspace: false,
        offerRemoveWorkspace: false,
      ),
    );

    expect(find.text('Archive Workspace'), findsNothing);
    expect(find.text('Remove Workspace'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.byTooltip('Pull Request Actions'), findsNothing);
  });

  testWidgets('omits workspace actions after the PR is closed', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .closed)),
    );

    expect(find.text('Archive Workspace'), findsNothing);
    expect(find.text('Remove Workspace'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.byTooltip('Pull Request Actions'), findsNothing);
  });
}
