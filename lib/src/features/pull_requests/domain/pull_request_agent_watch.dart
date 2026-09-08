import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';

enum PullRequestAgentWatchMode { fix, fixAndMerge }

enum PullRequestAgentWatchAction { none, dispatchFix, merge, stop }

class const PullRequestAgentWatchSession({
  required final String workspaceId,
  required final int reviewNumber,
  required final PullRequestAgentWatchMode mode,
  required final AgentTaskDispatchBinding binding,
  required final WorkspacePullRequestScope scope,
  final String? lastDispatchedFailureSignature,
  final String? lastMergedHeadSha,
});

class const PullRequestAgentWatchSnapshot({
  final bool loaded = true,
  final HostedReview? review,
  final ReviewChecksRollup checksRollup = ReviewChecksRollup.none,
});

class const PullRequestAgentWatchEvaluation({
  required final PullRequestAgentWatchAction action,
  final String? failureSignature,
  final String? headSha,
});

String pullRequestAgentWatchFailureSignature({
  required int reviewNumber,
  required String? headSha,
}) {
  return '$reviewNumber:${headSha ?? ''}';
}

String pullRequestAgentWatchModeLabel(PullRequestAgentWatchMode mode) {
  return switch (mode) {
    PullRequestAgentWatchMode.fix => 'Watching: Fix',
    PullRequestAgentWatchMode.fixAndMerge => 'Watching: Fix and Merge',
  };
}

PullRequestAgentWatchEvaluation evaluatePullRequestAgentWatch({
  required PullRequestAgentWatchSession session,
  required PullRequestAgentWatchSnapshot? snapshot,
}) {
  if (snapshot == null || !snapshot.loaded) {
    return const PullRequestAgentWatchEvaluation(action: .none);
  }
  final review = snapshot.review;
  if (review == null || review.number != session.reviewNumber) {
    return const PullRequestAgentWatchEvaluation(action: .stop);
  }
  if (review.state == HostedReviewState.merged ||
      review.state == HostedReviewState.closed) {
    return const PullRequestAgentWatchEvaluation(action: .stop);
  }
  final rollup = snapshot.checksRollup;
  final headSha = review.headSha;
  if (rollup == ReviewChecksRollup.failure) {
    final signature = pullRequestAgentWatchFailureSignature(
      reviewNumber: review.number,
      headSha: headSha,
    );
    if (signature == session.lastDispatchedFailureSignature) {
      return PullRequestAgentWatchEvaluation(
        action: .none,
        failureSignature: signature,
        headSha: headSha,
      );
    }
    return PullRequestAgentWatchEvaluation(
      action: .dispatchFix,
      failureSignature: signature,
      headSha: headSha,
    );
  }
  if (session.mode == PullRequestAgentWatchMode.fixAndMerge &&
      rollup == ReviewChecksRollup.success &&
      review.state == HostedReviewState.open &&
      review.mergeable == HostedReviewMergeable.mergeable &&
      headSha != null &&
      headSha.isNotEmpty &&
      headSha != session.lastMergedHeadSha) {
    return PullRequestAgentWatchEvaluation(action: .merge, headSha: headSha);
  }
  return PullRequestAgentWatchEvaluation(action: .none, headSha: headSha);
}
