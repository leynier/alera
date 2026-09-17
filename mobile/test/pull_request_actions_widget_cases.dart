part of 'pull_request_actions_test.dart';

void _registerPullRequestActionsWidgetTests() {
  testWidgets('merging asks for confirmation and shows the new state', (
    tester,
  ) async {
    final client = _client(_snapshot())
      ..nextSnapshot = _snapshot(state: 'MERGED');
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.text('Squash and Merge'));
    await tester.pumpAndSettle();
    expect(find.text('Squash and Merge PR #700?'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Squash and Merge').last,
    );
    await tester.pumpAndSettle();

    expect(client.calls, contains('mergePullRequest 700 squash'));
    expect(find.text('Merged'), findsOneWidget);
  });

  testWidgets('other actions live in the overflow sheet', (tester) async {
    final client = _client(_snapshot());
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Pull Request'));
    await tester.pumpAndSettle();
    expect(find.text('Close Pull Request #700?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Close Pull Request'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('closePullRequest 700'));
  });

  testWidgets('a failed action reports the runtime error', (tester) async {
    final client = _client(_snapshot())
      ..actionError = StateError('GitHub cannot merge this pull request yet.');
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.text('Squash and Merge'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Squash and Merge').last,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('GitHub cannot merge this pull request yet.'),
      findsOneWidget,
    );
  });

  testWidgets('posts a comment and keeps the draft when it fails', (
    tester,
  ) async {
    final client = _client(_snapshot())..actionError = StateError('Offline.');
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.scrollUntilVisible(find.text('Add Comment'), 200);
    await tester.tap(find.text('Add Comment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Looks good');
    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();

    expect(find.text('Offline.'), findsOneWidget);
    expect(find.text('Looks good'), findsOneWidget);

    client.actionError = null;
    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('commentOnPullRequest 700 Looks good'));
    expect(find.text('Post Comment'), findsNothing);
  });

  testWidgets('replies in a review thread and edits only own comments', (
    tester,
  ) async {
    final client = _client(
      _snapshot(
        comments: <Map<String, Object?>>[
          <String, Object?>{
            'id': 11,
            'author': 'me',
            'body': 'Mine',
            'canEdit': true,
          },
          <String, Object?>{
            'id': 21,
            'author': 'reviewer',
            'body': 'Rename this',
            'kind': 'review',
            'source': 'reviewThread',
            'threadId': 'T1',
            'path': 'lib/a.dart',
            'line': 3,
          },
        ],
      ),
    );
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.byTooltip('Edit Comment'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Reply'), 200);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Reply On lib/a.dart:3'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Done');
    await tester.tap(find.widgetWithText(FilledButton, 'Reply'));
    await tester.pumpAndSettle();
    expect(client.calls, contains('commentOnPullRequest 700 Done reply:21'));

    await tester.scrollUntilVisible(find.byTooltip('Edit Comment'), -200);
    await tester.tap(find.byTooltip('Edit Comment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Mine, edited');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      client.calls,
      contains('editPullRequestComment 700 11 Mine, edited'),
    );
  });

  testWidgets('without a review, links one or creates one', (tester) async {
    final client = _client(_snapshot(withReview: false))
      ..nextSnapshot = _snapshot();
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.text('Create Pull Request'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'feat: mobile actions',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create Pull Request'));
    await tester.pumpAndSettle();

    expect(
      client.calls,
      contains('createPullRequest main feat: mobile actions draft:false'),
    );
    expect(find.text('feat: mobile actions'), findsOneWidget);
  });

  testWidgets('link asks for a number or url', (tester) async {
    final client = _client(_snapshot(withReview: false));
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.text('Link Pull Request'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '#42');
    await tester.tap(find.widgetWithText(FilledButton, 'Link'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('linkPullRequest #42'));
  });

  testWidgets('a conflicting pull request keeps merge as a disabled primary', (
    tester,
  ) async {
    final client = _client(_snapshot(mergeable: 'CONFLICTING'));
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    final primary = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Squash and Merge'),
    );
    expect(primary.onPressed, isNull);

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Convert To Draft'), findsOneWidget);
    expect(find.text('Rebase and Merge'), findsNothing);
  });

  testWidgets('a failed refresh keeps the snapshot and reports the error', (
    tester,
  ) async {
    final client = _client(_snapshot());
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    client.pullRequestSnapshotError = StateError('The runtime is unreachable.');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('feat: mobile actions'), findsOneWidget);
    expect(find.text('The runtime is unreachable.'), findsOneWidget);
  });

  testWidgets('generates the title and description with AI Assist', (
    tester,
  ) async {
    final client = _client(_snapshot(withReview: false, aiAssistEnabled: true))
      ..pullRequestDetailsSupported = true
      ..generatedDetails = (
        title: 'Add mobile pull request actions',
        body: 'Why it matters',
      );
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.text('Create Pull Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate With AI'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('generatePullRequestDetails main'));
    expect(find.text('Add mobile pull request actions'), findsOneWidget);
    expect(find.text('Why it matters'), findsOneWidget);
  });

  testWidgets('ships staged changes as a draft', (tester) async {
    final client = _client(_snapshot(withReview: false, aiAssistEnabled: true))
      ..pullRequestShipSupported = true
      ..nextSnapshot = _snapshot();
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.text('Ship Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staged Changes'));
    await tester.tap(find.text('Create As Draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ship'));
    await tester.pumpAndSettle();

    expect(
      client.calls,
      contains('shipPullRequest main draft:true staged:true'),
    );
    expect(find.text('feat: mobile actions'), findsOneWidget);
  });

  testWidgets('hides generation when AI Assist is off', (tester) async {
    final client = _client(_snapshot(withReview: false))
      ..pullRequestDetailsSupported = true
      ..pullRequestShipSupported = true;
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.text('Ship Changes'), findsNothing);

    await tester.tap(find.text('Create Pull Request'));
    await tester.pumpAndSettle();

    expect(find.text('Generate With AI'), findsNothing);
  });

  testWidgets('an older runtime keeps the panel read-only', (tester) async {
    final client = _client(_snapshot())..pullRequestActionsSupported = false;
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.textContaining('Comments are read-only'), findsOneWidget);
    expect(find.text('Squash and Merge'), findsNothing);
    expect(find.text('Add Comment'), findsNothing);
  });
}
