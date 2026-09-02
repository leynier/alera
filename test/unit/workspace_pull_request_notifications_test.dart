import 'package:alera/src/features/pull_requests/application/workspace_pull_request_notifications.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkspacePullRequestSummary', () {
    test('failure dominates pending and keeps a bounded failure preview', () {
      final summary = _summary(
        checks: const <ReviewCheck>[
          ReviewCheck(name: 'build', status: .inProgress, conclusion: .pending),
          ReviewCheck(name: 'linux', status: .completed, conclusion: .failure),
          ReviewCheck(name: 'macos', status: .completed, conclusion: .timedOut),
          ReviewCheck(
            name: 'windows',
            status: .completed,
            conclusion: .cancelled,
          ),
          ReviewCheck(
            name: 'android',
            status: .completed,
            conclusion: .actionRequired,
          ),
        ],
      );

      expect(summary.checksRollup, ReviewChecksRollup.failure);
      expect(summary.checksFailed, isTrue);
      expect(summary.pendingCheckCount, 1);
      expect(summary.failedCheckCount, 4);
      expect(summary.failingCheckNames, <String>['linux', 'macos', 'windows']);
    });

    test('reports merge conflicts only for open pull requests', () {
      final open = _summary(mergeable: .conflicting);
      final merged = _summary(state: .merged, mergeable: .conflicting);

      expect(open.hasMergeConflict, isTrue);
      expect(merged.hasMergeConflict, isFalse);
    });
  });

  group('WorkspacePullRequestFailureTracker', () {
    test('does not replay failures already present at startup', () {
      final tracker = WorkspacePullRequestFailureTracker();
      final failed = <String, WorkspacePullRequestSummary>{
        'workspace': _failedSummary(),
      };

      expect(tracker.pending(failed), isEmpty);
      expect(tracker.pending(failed), isEmpty);
    });

    test('notifies once per failure transition and again after recovery', () {
      final tracker = WorkspacePullRequestFailureTracker();
      final pending = <String, WorkspacePullRequestSummary>{
        'workspace': _summary(checks: const <ReviewCheck>[_pendingCheck]),
      };
      final failed = <String, WorkspacePullRequestSummary>{
        'workspace': _failedSummary(),
      };
      final successful = <String, WorkspacePullRequestSummary>{
        'workspace': _summary(checks: const <ReviewCheck>[_successfulCheck]),
      };

      tracker.baseline(pending);
      expect(tracker.pending(failed), hasLength(1));
      expect(tracker.pending(failed), isEmpty);
      expect(tracker.pending(successful), isEmpty);
      expect(tracker.pending(failed), hasLength(1));
    });

    test('does not repeat while more checks fail on the same head', () {
      final tracker = WorkspacePullRequestFailureTracker();
      final first = <String, WorkspacePullRequestSummary>{
        'workspace': _failedSummary(headSha: 'sha-1'),
      };
      final second = <String, WorkspacePullRequestSummary>{
        'workspace': _summary(
          headSha: 'sha-1',
          checks: const <ReviewCheck>[
            ReviewCheck(
              name: 'build',
              status: .completed,
              conclusion: .failure,
            ),
            ReviewCheck(name: 'lint', status: .completed, conclusion: .failure),
          ],
        ),
      };

      tracker.baseline(first);

      expect(tracker.pending(second), isEmpty);
    });

    test('notifies for a new failing head commit on the same pull request', () {
      final tracker = WorkspacePullRequestFailureTracker();
      final first = <String, WorkspacePullRequestSummary>{
        'workspace': _failedSummary(headSha: 'sha-1'),
      };
      final second = <String, WorkspacePullRequestSummary>{
        'workspace': _failedSummary(headSha: 'sha-2'),
      };

      tracker.baseline(first);
      final pending = tracker.pending(second);

      expect(pending, hasLength(1));
      expect(pending.single.summary.review.headSha, 'sha-2');
    });

    test('does not notify for checks left failed after the PR is terminal', () {
      final tracker = WorkspacePullRequestFailureTracker();
      tracker.baseline(const <String, WorkspacePullRequestSummary>{});

      final pending = tracker.pending(<String, WorkspacePullRequestSummary>{
        'workspace': _summary(
          state: HostedReviewState.merged,
          checks: const <ReviewCheck>[
            ReviewCheck(
              name: 'build',
              status: .completed,
              conclusion: .failure,
            ),
          ],
        ),
      });

      expect(pending, isEmpty);
    });
  });

  group('pull request failure notification', () {
    test('payload round-trips and ignores other notification kinds', () {
      const payload = WorkspacePullRequestNotificationPayload(
        workspaceId: 'workspace',
        reviewNumber: 42,
        reviewUrl: 'https://github.com/acme/app/pull/42',
      );

      final decoded = decodeWorkspacePullRequestNotificationPayload(
        payload.encode(),
      );

      expect(decoded, isNotNull);
      expect(decoded!.workspaceId, 'workspace');
      expect(decoded.reviewNumber, 42);
      expect(decoded.reviewUrl, 'https://github.com/acme/app/pull/42');
      expect(
        decodeWorkspacePullRequestNotificationPayload(
          '{"kind":"agentStatus","workspaceId":"workspace"}',
        ),
        isNull,
      );
    });

    test('includes location and failing checks in the native notification', () {
      final notification = composeWorkspacePullRequestFailureNotification(
        failure: WorkspacePullRequestFailure(
          workspaceId: 'workspace',
          summary: _failedSummary(),
        ),
        projectName: 'Alera',
        workspaceName: 'PR status',
      );

      expect(notification.title, 'PR #42 checks failed');
      expect(notification.body, 'Alera · PR status — build');
      expect(notification.id, isPositive);
      expect(
        decodeWorkspacePullRequestNotificationPayload(notification.payload),
        isNotNull,
      );
    });
  });
}

const ReviewCheck _pendingCheck = ReviewCheck(
  name: 'build',
  status: .inProgress,
  conclusion: .pending,
);

const ReviewCheck _successfulCheck = ReviewCheck(
  name: 'build',
  status: .completed,
  conclusion: .success,
);

WorkspacePullRequestSummary _failedSummary({String headSha = 'sha-1'}) =>
    _summary(
      headSha: headSha,
      checks: const <ReviewCheck>[
        ReviewCheck(name: 'build', status: .completed, conclusion: .failure),
      ],
    );

WorkspacePullRequestSummary _summary({
  HostedReviewState state = HostedReviewState.open,
  HostedReviewMergeable mergeable = HostedReviewMergeable.mergeable,
  String headSha = 'sha-1',
  List<ReviewCheck> checks = const <ReviewCheck>[],
}) {
  return WorkspacePullRequestSummary.fromChecks(
    review: HostedReview(
      provider: .github,
      number: 42,
      title: 'feat: show PR status',
      state: state,
      url: 'https://github.com/acme/app/pull/42',
      headBranch: 'feat/pr-status',
      headSha: headSha,
      mergeable: mergeable,
    ),
    checks: checks,
  );
}
