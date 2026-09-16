part of 'pull_request_review_view_test.dart';

void _registerPullRequestReviewViewRemovalTests() {
  testWidgets('defaults a merged PR to Remove Workspace', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .merged)),
    );

    expect(find.text('Create Merge Commit'), findsNothing);
    expect(find.text('Close Pull Request'), findsNothing);
    expect(find.text('Remove Workspace'), findsOneWidget);
    expect(find.text('Unlink Pull Request'), findsNothing);
    final removeButton = tester.widget<Material>(
      find.byKey(
        const ValueKey<String>('pull-request-action-button-removeWorkspace'),
      ),
    );
    expect(removeButton.color, AleraTokens.error);

    await tester.tap(find.text('Remove Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Workspace?'), findsNothing);
    expect(callbacks.removeWorkspaceCalls, 1);
    expect(callbacks.unlinkCalls, 0);

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.text('Remove Workspace'), findsWidgets);
  });

  testWidgets('keeps unlink as the only merged action without removal', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(
        callbacks,
        review: _review.copyWith(state: .merged),
        offerRemoveWorkspace: false,
      ),
    );

    expect(find.text('Remove Workspace'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.byTooltip('Pull Request Actions'), findsNothing);
  });

  testWidgets('omits Remove Workspace after the PR is closed', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .closed)),
    );

    expect(find.text('Remove Workspace'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.byTooltip('Pull Request Actions'), findsNothing);
  });
}
