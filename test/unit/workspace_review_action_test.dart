import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/forge_auth_status.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_action_access.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_review_action.dart';
import 'package:flutter_test/flutter_test.dart';

const review = HostedReview(
  provider: .github,
  number: 123,
  title: 'Details',
  state: .open,
  url: 'https://github.com/a/b/pull/123',
  headSha: 'one',
  mergeable: .mergeable,
);
WorkspacePullRequestState ready() => const WorkspacePullRequestState(
  review: review,
  authStatus: ForgeAuthStatus.authenticated,
  checksLoaded: true,
  actionAccess: ReviewActionAccess(canMerge: true, canMarkReady: true),
  mergeMethods: [.squash],
  canChangeDraftStatus: true,
);
ReviewCheck check(ReviewCheckConclusion conclusion) => ReviewCheck(
  name: 'CI',
  status: conclusion == .pending ? .inProgress : .completed,
  conclusion: conclusion,
);
void main() {
  test('actions respect conflict, draft and checks priority', () {
    final state = ready();
    expect(
      resolveWorkspaceReviewAction(state).action,
      WorkspaceReviewAction.merge,
    );
    expect(
      resolveWorkspaceReviewAction(
        state.copyWith(
          review: review.copyWith(mergeable: .conflicting),
          checks: [check(.failure)],
        ),
      ).action,
      WorkspaceReviewAction.resolve,
    );
    expect(
      resolveWorkspaceReviewAction(
        state.copyWith(
          review: review.copyWith(state: .draft),
          checks: [check(.failure)],
        ),
      ).action,
      WorkspaceReviewAction.ready,
    );
    expect(
      resolveWorkspaceReviewAction(state.copyWith(checks: [check(.failure)]))
          .action,
      WorkspaceReviewAction.fix,
    );
    expect(
      resolveWorkspaceReviewAction(state.copyWith(checks: [check(.pending)]))
          .action,
      isNull,
    );
  });
  test('unknown, unavailable and denied capabilities never enable merge', () {
    for (final state in [
      ready().copyWith(checksLoaded: false),
      ready().copyWith(checksErrorMessage: 'offline'),
      ready().copyWith(review: review.copyWith(mergeable: .unknown)),
      ready().copyWith(actionAccess: const ReviewActionAccess()),
      ready().copyWith(actionAccess: const ReviewActionAccess(canMerge: false)),
      ready().copyWith(mergeMethods: []),
      ready().copyWith(authStatus: .notAuthenticated),
      ready().copyWith(action: .merge),
    ]) {
      expect(resolveWorkspaceReviewAction(state).action, isNull);
      expect(resolveWorkspaceReviewAction(state).hint, isNotNull);
    }
  });
  test('closed and merged PRs expose no mutation', () {
    for (final status in [HostedReviewState.closed, HostedReviewState.merged]) {
      expect(
        resolveWorkspaceReviewAction(
          ready().copyWith(review: review.copyWith(state: status)),
        ).action,
        isNull,
      );
    }
  });
  test('confirmation fingerprint changes when HEAD or base changes', () {
    expect(
      reviewActionFingerprint(ready()),
      isNot(
        reviewActionFingerprint(
          ready().copyWith(review: review.copyWith(headSha: 'two')),
        ),
      ),
    );
    expect(
      reviewActionFingerprint(ready()),
      isNot(
        reviewActionFingerprint(
          ready().copyWith(review: review.copyWith(baseBranch: 'other')),
        ),
      ),
    );
  });
}
