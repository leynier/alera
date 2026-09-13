import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch_scope.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_thread_backlog.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';

enum PullRequestAgentWatchMode { fix, fixAndMerge }

enum PullRequestAgentWatchAction { none, dispatch, merge, stop }

/// What the watch already asked the agent to fix on [headSha].
///
/// Dispatch only reacts to additions: a reviewer resolving one of several
/// threads shrinks the pending set without adding work, so it must not send
/// the agent the same request again.
class const PullRequestAgentWatchDispatchMark({
  final String? headSha,
  final bool checksFailed = false,
  final bool conflict = false,
  final Set<String> threadIds = const <String>{},
});

class const PullRequestAgentWatchSession({
  required final String workspaceId,
  required final int reviewNumber,
  required final PullRequestAgentWatchMode mode,
  required final AgentTaskDispatchBinding binding,
  required final WorkspacePullRequestScope scope,
  final PullRequestAgentWatchScope watchScope =
      PullRequestAgentWatchScope.defaults,
  final PullRequestAgentWatchDispatchMark? lastDispatch,
  final String? lastMergedHeadSha,
}) {
  PullRequestAgentWatchSession copyWith({
    AgentTaskDispatchBinding? binding,
    PullRequestAgentWatchDispatchMark? lastDispatch,
    String? lastMergedHeadSha,
  }) {
    return PullRequestAgentWatchSession(
      workspaceId: workspaceId,
      reviewNumber: reviewNumber,
      mode: mode,
      binding: binding ?? this.binding,
      scope: scope,
      watchScope: watchScope,
      lastDispatch: lastDispatch ?? this.lastDispatch,
      lastMergedHeadSha: lastMergedHeadSha ?? this.lastMergedHeadSha,
    );
  }
}

class const PullRequestAgentWatchSnapshot({
  final bool loaded = true,
  final HostedReview? review,
  final ReviewChecksRollup checksRollup = ReviewChecksRollup.none,
  final List<ReviewComment> comments = const <ReviewComment>[],
});

/// Problems inside the watch scope that an agent should fix.
class const PullRequestAgentWatchConcerns({
  final bool checksFailed = false,
  final bool conflict = false,
  final List<PendingReviewThread> threads = const <PendingReviewThread>[],
}) {
  bool get isEmpty => !checksFailed && !conflict && threads.isEmpty;

  Set<String> get threadIds => <String>{
    for (final thread in threads) thread.id,
  };
}

class const PullRequestAgentWatchEvaluation({
  required final PullRequestAgentWatchAction action,
  final PullRequestAgentWatchConcerns concerns =
      const PullRequestAgentWatchConcerns(),
  final String? headSha,
});

/// `unknown` mergeability is not a conflict: GitHub recomputes it after every
/// push, so treating it as one would dispatch on each new commit.
PullRequestAgentWatchConcerns pullRequestAgentWatchConcerns({
  required PullRequestAgentWatchSnapshot snapshot,
  required PullRequestAgentWatchScope scope,
}) {
  final review = snapshot.review;
  return PullRequestAgentWatchConcerns(
    checksFailed:
        scope.checks && snapshot.checksRollup == ReviewChecksRollup.failure,
    conflict:
        scope.conflicts &&
        review?.mergeable == HostedReviewMergeable.conflicting,
    threads: scope.comments
        ? pendingReviewThreads(
            comments: snapshot.comments,
            reviewAuthor: review?.author,
          )
        : const <PendingReviewThread>[],
  );
}

bool pullRequestAgentWatchInjectsOnStart(
  PullRequestAgentWatchConcerns concerns,
) {
  return !concerns.isEmpty;
}

/// Whether [concerns] add anything the agent was not already asked to fix.
bool pullRequestAgentWatchHasNewConcerns({
  required PullRequestAgentWatchDispatchMark? mark,
  required String? headSha,
  required PullRequestAgentWatchConcerns concerns,
}) {
  if (concerns.isEmpty) {
    return false;
  }
  if (mark == null || mark.headSha != headSha) {
    return true;
  }
  return (concerns.checksFailed && !mark.checksFailed) ||
      (concerns.conflict && !mark.conflict) ||
      concerns.threadIds.difference(mark.threadIds).isNotEmpty;
}

/// Records a dispatch. On the same head the mark accumulates, so a thread
/// that is resolved and reopened does not repeat the request; a new head
/// starts over because the agent's last push may not have fixed everything.
PullRequestAgentWatchDispatchMark pullRequestAgentWatchDispatchMark({
  required PullRequestAgentWatchDispatchMark? previous,
  required String? headSha,
  required PullRequestAgentWatchConcerns concerns,
}) {
  final carried = previous != null && previous.headSha == headSha
      ? previous
      : null;
  return PullRequestAgentWatchDispatchMark(
    headSha: headSha,
    checksFailed: concerns.checksFailed || (carried?.checksFailed ?? false),
    conflict: concerns.conflict || (carried?.conflict ?? false),
    threadIds: <String>{...?carried?.threadIds, ...concerns.threadIds},
  );
}

String pullRequestAgentWatchModeLabel(PullRequestAgentWatchMode mode) {
  return switch (mode) {
    PullRequestAgentWatchMode.fix => 'Watching: Fix',
    PullRequestAgentWatchMode.fixAndMerge => 'Watching: Fix and Merge',
  };
}

/// Keep the watch eligible to retry when dispatch did not actually send.
PullRequestAgentWatchSession pullRequestAgentWatchAfterDispatch({
  required PullRequestAgentWatchSession session,
  required AgentTaskDispatchResult? result,
  required PullRequestAgentWatchConcerns concerns,
  required String? headSha,
}) {
  if (result == null) {
    return session;
  }
  return session.copyWith(
    binding: result.binding,
    lastDispatch: pullRequestAgentWatchDispatchMark(
      previous: session.lastDispatch,
      headSha: headSha,
      concerns: concerns,
    ),
  );
}

/// Keep the watch eligible to retry when the forge merge did not succeed.
PullRequestAgentWatchSession pullRequestAgentWatchAfterMerge({
  required PullRequestAgentWatchSession session,
  required bool merged,
  required String? headSha,
}) {
  if (!merged) {
    return session;
  }
  return session.copyWith(lastMergedHeadSha: headSha);
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
  final headSha = review.headSha;
  final concerns = pullRequestAgentWatchConcerns(
    snapshot: snapshot,
    scope: session.watchScope,
  );
  if (pullRequestAgentWatchHasNewConcerns(
    mark: session.lastDispatch,
    headSha: headSha,
    concerns: concerns,
  )) {
    return PullRequestAgentWatchEvaluation(
      action: .dispatch,
      concerns: concerns,
      headSha: headSha,
    );
  }
  if (session.mode == PullRequestAgentWatchMode.fixAndMerge &&
      snapshot.checksRollup == ReviewChecksRollup.success &&
      review.state == HostedReviewState.open &&
      review.mergeable == HostedReviewMergeable.mergeable &&
      concerns.threads.isEmpty &&
      headSha != null &&
      headSha.isNotEmpty &&
      headSha != session.lastMergedHeadSha) {
    return PullRequestAgentWatchEvaluation(action: .merge, headSha: headSha);
  }
  return PullRequestAgentWatchEvaluation(
    action: .none,
    concerns: concerns,
    headSha: headSha,
  );
}
