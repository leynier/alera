part of 'pull_request_actions_test.dart';

void _registerPullRequestActionsRemovalTests() {
  testWidgets('defaults a merged PR to Remove Workspace', (tester) async {
    final client = _client(_snapshot(state: 'MERGED'));
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.text('Create Merge Commit'), findsNothing);
    expect(find.text('Close Pull Request'), findsNothing);
    expect(find.text('Remove Workspace'), findsOneWidget);
    expect(find.text('Unlink Pull Request'), findsNothing);

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.text('Remove Workspace'), findsOneWidget);
  });

  testWidgets('keeps unlink as the only merged action without removal', (
    tester,
  ) async {
    final client = _client(_snapshot(state: 'MERGED'))
      ..supportsWorkspaceMutations = false;
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.text('Remove Workspace'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.byTooltip('Pull Request Actions'), findsNothing);
  });

  testWidgets('omits Remove Workspace after the PR is closed', (tester) async {
    final client = _client(_snapshot(state: 'CLOSED'));
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    expect(find.text('Remove Workspace'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.byTooltip('Pull Request Actions'), findsNothing);
  });

  testWidgets('merged pull requests offer the sidebar Remove Workspace flow', (
    tester,
  ) async {
    final client = _client(_snapshot(state: 'MERGED'));
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

    await tester.tap(find.text('Remove Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Workspace'), findsOneWidget);
    expect(client.calls, isNot(contains('removeWorkspace workspace-1 true')));

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('removeWorkspace workspace-1 true'));
  });

  testWidgets('removing a workspace after merge returns to the list', (
    tester,
  ) async {
    final client = _client(_snapshot(state: 'MERGED'));
    addTearDown(client.dispose);
    await _openPullRequest(
      tester,
      client,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkspaceTabsScreen(
                      hostId: 'host-1',
                      workspace: _workspace,
                    ),
                  ),
                );
              },
              child: const Text('Workspace List'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Remove Workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Workspace List'), findsOneWidget);
    expect(find.text('Remove Workspace'), findsNothing);
    expect(client.calls, contains('removeWorkspace workspace-1 true'));
  });
}
