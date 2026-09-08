import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
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
  VoidCallback? onFixFailedChecks,
  VoidCallback? onWatchAndFix,
  VoidCallback? onWatchFixAndMerge,
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
        onFixFailedChecks: onFixFailedChecks,
        onWatchAndFix: onWatchAndFix,
        onWatchFixAndMerge: onWatchFixAndMerge,
        onStopAgentWatch: onStopAgentWatch,
      ),
    ),
  );
}

void main() {
  testWidgets('offers failed-check dispatch and watch actions', (tester) async {
    var fixCalls = 0;
    var watchFixCalls = 0;
    var watchMergeCalls = 0;
    await tester.pumpWidget(
      _wrap(
        checks: const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .completed, conclusion: .failure),
        ],
        onFixFailedChecks: () => fixCalls++,
        onWatchAndFix: () => watchFixCalls++,
        onWatchFixAndMerge: () => watchMergeCalls++,
      ),
    );

    expect(find.text('Fix Failed Checks'), findsOneWidget);
    await tester.tap(find.text('Fix Failed Checks'));
    await tester.pump();
    expect(fixCalls, 1);

    await tester.tap(find.byTooltip('Ask Agent'));
    await tester.pumpAndSettle();
    expect(find.text('Watch and Fix'), findsOneWidget);
    expect(find.text('Watch, Fix and Merge'), findsOneWidget);
    await tester.tap(find.text('Watch and Fix'));
    await tester.pumpAndSettle();
    expect(watchFixCalls, 1);
    expect(watchMergeCalls, 0);

    await tester.tap(find.byTooltip('Ask Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch, Fix and Merge'));
    await tester.pumpAndSettle();
    expect(watchMergeCalls, 1);
  });

  testWidgets('shows stop watching while a watch is active', (tester) async {
    var stopCalls = 0;
    await tester.pumpWidget(
      _wrap(agentWatchMode: .fix, onStopAgentWatch: () => stopCalls++),
    );

    expect(find.text('Watching: Fix'), findsOneWidget);
    expect(find.text('Fix Failed Checks'), findsNothing);
    await tester.tap(find.text('Stop Watching'));
    await tester.pump();
    expect(stopCalls, 1);
  });

  testWidgets('shows stop watching for fix-and-merge mode', (tester) async {
    await tester.pumpWidget(
      _wrap(agentWatchMode: .fixAndMerge, onStopAgentWatch: () {}),
    );
    expect(find.text('Watching: Fix and Merge'), findsOneWidget);
    expect(find.text('Stop Watching'), findsOneWidget);
  });
}
