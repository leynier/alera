import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_summary.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_pull_request_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses standard lifecycle icons and colors', (tester) async {
    await _pump(tester, _summary(state: .open));
    _expectIcon(tester, AleraIcons.gitPullRequest, AleraTokens.success);
    expect(_tooltip(tester), contains('Ready to merge'));

    await _pump(tester, _summary(state: .draft));
    _expectIcon(
      tester,
      AleraIcons.gitPullRequestDraft,
      AleraTokens.foregroundMuted,
    );
    expect(_tooltip(tester), contains('Draft'));

    await _pump(tester, _summary(state: .merged));
    _expectIcon(tester, AleraIcons.gitMerge, AleraTokens.done);
    expect(_tooltip(tester), contains('Merged'));

    await _pump(tester, _summary(state: .closed));
    _expectIcon(tester, AleraIcons.gitPullRequestClosed, AleraTokens.error);
    expect(_tooltip(tester), contains('Closed without merging'));
  });

  testWidgets('shows a static running-check badge', (tester) async {
    await _pump(
      tester,
      _summary(
        checks: const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .inProgress, conclusion: .pending),
        ],
      ),
    );

    _expectIcon(tester, AleraIcons.gitPullRequest, AleraTokens.success);
    _expectIcon(tester, AleraIcons.loading, AleraTokens.warning);
    expect(_tooltip(tester), contains('1 check running'));
  });

  testWidgets('shows failed checks and their names', (tester) async {
    await _pump(
      tester,
      _summary(
        checks: const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .completed, conclusion: .failure),
        ],
      ),
    );

    _expectIcon(tester, AleraIcons.cancel, AleraTokens.error);
    expect(_tooltip(tester), contains('Checks failed'));
    expect(_tooltip(tester), contains('build'));
  });
}

Future<void> _pump(WidgetTester tester, WorkspacePullRequestSummary summary) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: WorkspacePullRequestStatusIndicator(summary: summary),
        ),
      ),
    ),
  );
}

void _expectIcon(WidgetTester tester, IconData data, Color color) {
  final icon = tester.widget<Icon>(find.byIcon(data));
  expect(icon.color, color);
}

String _tooltip(WidgetTester tester) {
  return tester.widget<Tooltip>(find.byType(Tooltip)).message ?? '';
}

WorkspacePullRequestSummary _summary({
  HostedReviewState state = HostedReviewState.open,
  List<ReviewCheck> checks = const <ReviewCheck>[],
}) {
  return WorkspacePullRequestSummary.fromChecks(
    review: HostedReview(
      provider: .github,
      number: 42,
      title: 'feat: show PR status',
      state: state,
      url: 'https://github.com/acme/app/pull/42',
      mergeable: .mergeable,
    ),
    checks: checks,
  );
}
