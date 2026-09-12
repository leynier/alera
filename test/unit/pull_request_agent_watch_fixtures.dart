import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';

const pullRequestWatchTestScope = WorkspacePullRequestScope(
  workspaceId: 'workspace-1',
  repoPath: '/repo',
);

const pullRequestWatchTestDispatchResult = AgentTaskDispatchResult(
  workspaceId: 'workspace-1',
  tabId: 'tab-2',
  openedNewTab: true,
  label: 'Codex Builder',
  profileId: 'profile-1',
);

/// Pull request #42 by `leynier`, as the watch sees it on one poll.
PullRequestAgentWatchSnapshot pullRequestWatchSnapshot({
  HostedReviewState state = HostedReviewState.open,
  HostedReviewMergeable mergeable = HostedReviewMergeable.unknown,
  ReviewChecksRollup rollup = ReviewChecksRollup.none,
  String headSha = 'abc123',
  List<ReviewComment> comments = const <ReviewComment>[],
}) {
  return PullRequestAgentWatchSnapshot(
    review: HostedReview(
      provider: .github,
      number: 42,
      title: 'feat: example',
      state: state,
      url: 'https://github.com/leynier/alera/pull/42',
      author: 'leynier',
      headSha: headSha,
      mergeable: mergeable,
    ),
    checksRollup: rollup,
    comments: comments,
  );
}

/// One inline review comment in thread [id].
ReviewComment pullRequestWatchThread(
  String id, {
  String author = 'pullfrog',
  bool resolved = false,
}) {
  return ReviewComment(
    id: 'thread:$id:1',
    author: author,
    body: 'Remove the unused alias.',
    createdAt: DateTime.utc(2026, 9, 12),
    kind: .review,
    path: 'lib/a.dart',
    line: 3,
    resolved: resolved,
    locator: ReviewCommentLocator(
      source: .reviewThread,
      commentId: '1',
      parentId: id,
    ),
  );
}
