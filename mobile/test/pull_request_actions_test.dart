import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

MobilePullRequestSnapshot _snapshot({
  String state = 'OPEN',
  bool isDraft = false,
  String? mergeable = 'MERGEABLE',
  List<String> mergeMethods = const <String>['squash', 'rebase'],
  List<Map<String, Object?>> comments = const <Map<String, Object?>>[],
  bool withReview = true,
  bool aiAssistEnabled = false,
}) {
  return MobilePullRequestSnapshot.fromJson(<String, Object?>{
    'branch': 'feat/actions',
    'provider': 'github',
    'authStatus': 'authenticated',
    'identity': <String, Object?>{'owner': 'leynier', 'repo': 'alera'},
    'canComment': state == 'OPEN',
    'viewerLogin': 'me',
    'mergeMethods': mergeMethods,
    'baseBranches': <String>['develop', 'feat/actions', 'main'],
    'suggestedBaseBranch': 'main',
    'aiAssistEnabled': aiAssistEnabled,
    'review': withReview
        ? <String, Object?>{
            'number': 700,
            'title': 'feat: mobile actions',
            'state': state,
            'isDraft': isDraft,
            'mergeable': mergeable,
            'url': 'https://github.com/leynier/alera/pull/700',
            'checks': <Object?>[],
            'comments': comments,
          }
        : null,
    if (!withReview)
      'unavailableReason': 'No open pull request is linked to this branch.',
  });
}

void main() {
  group('availablePullRequestReviewActions', () {
    List<String> labels(MobilePullRequestSnapshot snapshot) => <String>[
      for (final action in availablePullRequestReviewActions(snapshot))
        action.label,
    ];

    test('an open pull request offers merges, draft, close, and unlink', () {
      expect(labels(_snapshot()), <String>[
        'Squash and Merge',
        'Rebase and Merge',
        'Convert To Draft',
        'Close Pull Request',
        'Unlink Pull Request',
      ]);
    });

    test('a draft offers ready first and cannot merge', () {
      final snapshot = _snapshot(isDraft: true);
      expect(labels(snapshot).first, 'Mark Ready For Review');
      expect(labels(snapshot), isNot(contains('Convert To Draft')));
      final merge = availablePullRequestReviewActions(snapshot)
          .firstWhere((action) => action.kind == .merge);
      expect(pullRequestReviewActionEnabled(merge, snapshot.review!), isFalse);
    });

    test('a conflicting pull request lists merges but disables them', () {
      final snapshot = _snapshot(mergeable: 'CONFLICTING');
      final merge = availablePullRequestReviewActions(snapshot).first;
      expect(merge.kind, MobilePullRequestReviewActionKind.merge);
      expect(pullRequestReviewActionEnabled(merge, snapshot.review!), isFalse);
    });

    test('a merged pull request only offers unlink', () {
      expect(labels(_snapshot(state: 'MERGED')), <String>[
        'Unlink Pull Request',
      ]);
    });

    test('unknown merge methods are ignored', () {
      expect(
        labels(_snapshot(mergeMethods: <String>['octopus', 'mergeCommit'])),
        contains('Create Merge Commit'),
      );
    });
  });

  test('confirmation copy matches the desktop dialogs', () {
    const close = MobilePullRequestReviewAction(kind: .close);
    final copy = pullRequestActionConfirmation(close, 7);
    expect(copy.title, 'Close Pull Request #7?');
    expect(copy.destructive, isTrue);
    const squash = MobilePullRequestReviewAction(
      kind: .merge,
      method: MobilePullRequestMergeMethod.squash,
    );
    expect(
      pullRequestActionConfirmation(squash, 7).title,
      'Squash and Merge PR #7?',
    );
  });

  test('runtime errors keep their wording', () {
    expect(
      pullRequestActionErrorMessage(StateError('Push first.')),
      'Push first.',
    );
    expect(
      pullRequestActionErrorMessage(TimeoutException('slow')),
      'The paired computer did not answer in time.',
    );
  });

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

  test('a write snapshot survives a refresh that started before it', () async {
    final client = _client(_snapshot());
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final provider = pullRequestControllerProvider('host-1', 'workspace-1');
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    final gate = Completer<void>();
    client.pullRequestSnapshotGate = gate;
    final refresh = notifier.refresh();
    notifier.applySnapshot(_snapshot(state: 'MERGED'));
    gate.complete();

    expect(await refresh, isNull);
    expect(container.read(provider).value?.review?.state, 'MERGED');
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

  testWidgets('hides generation when AI Assist is off', (tester) async {
    final client = _client(_snapshot(withReview: false))
      ..pullRequestDetailsSupported = true;
    addTearDown(client.dispose);
    await _openPullRequest(tester, client);

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

FakeTerminalClient _client(MobilePullRequestSnapshot snapshot) {
  return FakeTerminalClient()
    ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
    ..pullRequestsSupported = true
    ..pullRequestActionsSupported = true
    ..pullRequest = snapshot;
}

Future<void> _openPullRequest(
  WidgetTester tester,
  FakeTerminalClient client,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const WorkspaceTabsScreen(
          hostId: 'host-1',
          workspace: WorkspaceSummary(
            id: 'workspace-1',
            projectId: 'project-1',
            name: 'Workspace',
            path: '/repo',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('More Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pull Request'));
  await tester.pumpAndSettle();
}
