import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _review = HostedReview(
  provider: .github,
  number: 42,
  title: 'feat: original',
  state: .open,
  url: 'https://github.com/leynier/alera/pull/42',
);

Widget _wrap({
  List<ReviewCheck> checks = const <ReviewCheck>[],
  PullRequestAgentWatchMode? agentWatchMode,
  PullRequestAgentWatchScope agentWatchScope =
      PullRequestAgentWatchScope.defaults,
  ValueChanged<PullRequestAgentWatchScope>? onAgentWatchScopeChanged,
  VoidCallback? onFixFailedChecks,
  ValueChanged<PullRequestAgentWatchScope>? onWatchAndFix,
  ValueChanged<PullRequestAgentWatchScope>? onWatchFixAndMerge,
  VoidCallback? onStopAgentWatch,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestReviewView(
        review: _review,
        checks: checks,
        comments: const <ReviewComment>[],
        baseBranches: const <String>['main'],
        mergeMethods: const <ReviewMergeMethod>[ReviewMergeMethod.mergeCommit],
        canCloseReview: true,
        canChangeDraftStatus: true,
        canComment: false,
        action: null,
        onOpenUrl: (_) async {},
        onUnlink: () async {},
        onMerge: (_) async {},
        onClose: () async {},
        onDraftStatusChanged: (_) async {},
        onAddComment: (_) async => true,
        onUpdate: (_) async => const UpdateReviewSuccess(_review),
        onLoadCheckDetails: (_) async => const ReviewCheckDetails(),
        agentWatchMode: agentWatchMode,
        agentWatchScope: agentWatchScope,
        onAgentWatchScopeChanged: onAgentWatchScopeChanged,
        onFixFailedChecks: onFixFailedChecks,
        onWatchAndFix: onWatchAndFix,
        onWatchFixAndMerge: onWatchFixAndMerge,
        onStopAgentWatch: onStopAgentWatch,
      ),
    ),
  );
}

Future<void> _openAskAgentMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ask Agent'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keeps the failed-check dispatch in the checks section', (
    tester,
  ) async {
    var fixCalls = 0;
    await tester.pumpWidget(
      _wrap(
        checks: const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .completed, conclusion: .failure),
        ],
        onFixFailedChecks: () => fixCalls++,
        onWatchAndFix: (_) {},
      ),
    );

    await tester.tap(find.text('Fix Failed Checks'));
    await tester.pump();
    expect(fixCalls, 1);
  });

  testWidgets('places Ask Agent in the pull request header', (tester) async {
    await tester.pumpWidget(_wrap(onWatchAndFix: (_) {}));

    final askAgent = tester.getTopLeft(find.byTooltip('Ask Agent'));
    final openInBrowser = tester.getTopLeft(find.byTooltip('Open In Browser'));
    final checksHeader = tester.getTopLeft(find.text('Checks'));
    expect(askAgent.dy, openInBrowser.dy);
    expect(askAgent.dy, lessThan(checksHeader.dy));
  });

  testWidgets('starts either watch mode with the chosen scope', (tester) async {
    final watchFixScopes = <PullRequestAgentWatchScope>[];
    final watchMergeScopes = <PullRequestAgentWatchScope>[];
    await tester.pumpWidget(
      _wrap(
        onWatchAndFix: watchFixScopes.add,
        onWatchFixAndMerge: watchMergeScopes.add,
      ),
    );

    await _openAskAgentMenu(tester);
    expect(find.text('Failed Checks'), findsOneWidget);
    expect(find.text('Review Comments'), findsOneWidget);
    expect(find.text('Merge Conflicts'), findsOneWidget);
    await tester.tap(find.text('Watch and Fix'));
    await tester.pumpAndSettle();
    expect(watchFixScopes, <PullRequestAgentWatchScope>[
      PullRequestAgentWatchScope.defaults,
    ]);

    await _openAskAgentMenu(tester);
    await tester.tap(find.text('Watch, Fix and Merge'));
    await tester.pumpAndSettle();
    expect(watchMergeScopes, <PullRequestAgentWatchScope>[
      PullRequestAgentWatchScope.defaults,
    ]);
  });

  testWidgets('toggling a scope keeps the menu open', (tester) async {
    final changes = <PullRequestAgentWatchScope>[];
    final watchFixScopes = <PullRequestAgentWatchScope>[];
    await tester.pumpWidget(
      _wrap(
        onAgentWatchScopeChanged: changes.add,
        onWatchAndFix: watchFixScopes.add,
      ),
    );

    await _openAskAgentMenu(tester);
    await tester.tap(find.text('Review Comments'));
    await tester.pumpAndSettle();

    expect(find.text('Watch and Fix'), findsOneWidget);
    expect(changes, <PullRequestAgentWatchScope>[
      const PullRequestAgentWatchScope(comments: false),
    ]);
    await tester.tap(find.text('Watch and Fix'));
    await tester.pumpAndSettle();
    expect(watchFixScopes, <PullRequestAgentWatchScope>[
      const PullRequestAgentWatchScope(comments: false),
    ]);
  });

  testWidgets('disables watch modes for an empty scope', (tester) async {
    var watchCalls = 0;
    await tester.pumpWidget(
      _wrap(
        agentWatchScope: const PullRequestAgentWatchScope(
          checks: false,
          comments: false,
          conflicts: false,
        ),
        onWatchAndFix: (_) => watchCalls++,
      ),
    );

    await _openAskAgentMenu(tester);
    await tester.tap(find.text('Watch and Fix'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(watchCalls, 0);
  });

  testWidgets('enables watch modes as soon as a scope is checked', (
    tester,
  ) async {
    final watchFixScopes = <PullRequestAgentWatchScope>[];
    await tester.pumpWidget(
      _wrap(
        agentWatchScope: const PullRequestAgentWatchScope(
          checks: false,
          comments: false,
          conflicts: false,
        ),
        onWatchAndFix: watchFixScopes.add,
      ),
    );

    await _openAskAgentMenu(tester);
    await tester.tap(find.text('Merge Conflicts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch and Fix'));
    await tester.pumpAndSettle();
    expect(watchFixScopes, <PullRequestAgentWatchScope>[
      const PullRequestAgentWatchScope(checks: false, comments: false),
    ]);
  });

  testWidgets('disables watch modes once every scope is unchecked', (
    tester,
  ) async {
    var watchCalls = 0;
    await tester.pumpWidget(_wrap(onWatchAndFix: (_) => watchCalls++));

    await _openAskAgentMenu(tester);
    for (final label in <String>[
      'Failed Checks',
      'Review Comments',
      'Merge Conflicts',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Watch and Fix'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(watchCalls, 0);
    expect(find.text('Watch and Fix'), findsOneWidget);
  });

  testWidgets('offers stop watching while a watch is active', (tester) async {
    var stopCalls = 0;
    await tester.pumpWidget(
      _wrap(
        checks: const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .completed, conclusion: .failure),
        ],
        agentWatchMode: .fix,
        onFixFailedChecks: () {},
        onStopAgentWatch: () => stopCalls++,
      ),
    );

    expect(find.text('Watching: Fix'), findsOneWidget);
    expect(find.text('Fix Failed Checks'), findsNothing);
    expect(find.byTooltip('Ask Agent'), findsNothing);
    await tester.tap(find.byTooltip('Watching: Fix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop Watching'));
    await tester.pumpAndSettle();
    expect(stopCalls, 1);
  });

  testWidgets('labels fix-and-merge mode while watching', (tester) async {
    await tester.pumpWidget(
      _wrap(agentWatchMode: .fixAndMerge, onStopAgentWatch: () {}),
    );
    expect(find.text('Watching: Fix and Merge'), findsOneWidget);
  });
}
