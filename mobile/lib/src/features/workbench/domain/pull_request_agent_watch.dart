import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';

enum PullRequestAgentWatchMode { fix, fixAndMerge }

enum PullRequestAgentWatchAction { none, dispatch, merge, stop }

enum PullRequestChecksRollup { none, pending, success, failure }

/// A review thread that still asks for a change.
class const PendingReviewThread({
  required final String id,
  final String? path,
  final int? line,
});

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
  required final String hostId,
  required final String workspaceId,
  required final int reviewNumber,
  required final PullRequestAgentWatchMode mode,
  required final AgentTaskDispatchBinding binding,
  final PullRequestAgentWatchScope watchScope =
      PullRequestAgentWatchScope.defaults,
  final PullRequestAgentWatchDispatchMark? lastDispatch,
  final String? lastMergedHeadSha,
  final String? lastError,
}) {
  PullRequestAgentWatchSession copyWith({
    AgentTaskDispatchBinding? binding,
    PullRequestAgentWatchDispatchMark? lastDispatch,
    String? lastMergedHeadSha,
    String? lastError,
    bool clearError = false,
  }) {
    return PullRequestAgentWatchSession(
      hostId: hostId,
      workspaceId: workspaceId,
      reviewNumber: reviewNumber,
      mode: mode,
      binding: binding ?? this.binding,
      watchScope: watchScope,
      lastDispatch: lastDispatch ?? this.lastDispatch,
      lastMergedHeadSha: lastMergedHeadSha ?? this.lastMergedHeadSha,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class const PullRequestAgentWatchSnapshot({
  final bool loaded = true,
  final MobilePullRequestReview? review,
  final PullRequestChecksRollup checksRollup = PullRequestChecksRollup.none,
  final List<MobilePullRequestComment> comments =
      const <MobilePullRequestComment>[],
  final bool commentsComplete = true,
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

/// Matches desktop `deriveReviewChecksRollup`: failure dominates, cancelled
/// counts as failure, then pending, then success. An empty list is [none].
PullRequestChecksRollup derivePullRequestChecksRollup(
  List<MobilePullRequestCheck> checks,
) {
  if (checks.isEmpty) {
    return PullRequestChecksRollup.none;
  }
  var anyPending = false;
  for (final check in checks) {
    final key = (check.bucket.isEmpty ? check.state : check.bucket)
        .toLowerCase();
    switch (key) {
      case 'fail' ||
          'failure' ||
          'error' ||
          'cancel' ||
          'cancelled' ||
          'timed_out' ||
          'timedout' ||
          'action_required':
        return PullRequestChecksRollup.failure;
      case 'pending' || 'in_progress' || 'queued' || 'waiting':
        anyPending = true;
      default:
        break;
    }
  }
  return anyPending
      ? PullRequestChecksRollup.pending
      : PullRequestChecksRollup.success;
}

bool pullRequestChecksFailed(List<MobilePullRequestCheck> checks) {
  return derivePullRequestChecksRollup(checks) ==
      PullRequestChecksRollup.failure;
}

/// Groups review comments into threads and keeps the ones an agent should
/// address. Conversation comments without a thread id cannot be resolved, so
/// they are ignored. A thread is dropped when it is resolved, when every
/// comment in it is outdated, or when [reviewAuthor] wrote all of it.
List<PendingReviewThread> pendingReviewThreads({
  required List<MobilePullRequestComment> comments,
  String? reviewAuthor,
}) {
  final threads = <String, List<MobilePullRequestComment>>{};
  for (final comment in comments) {
    final threadId = comment.threadId;
    if (threadId == null || threadId.isEmpty) {
      continue;
    }
    (threads[threadId] ??= <MobilePullRequestComment>[]).add(comment);
  }
  final author = reviewAuthor?.trim().toLowerCase();
  return <PendingReviewThread>[
    for (final MapEntry(key: id, value: thread) in threads.entries)
      if (!thread.every((comment) => comment.resolved) &&
          !thread.every((comment) => comment.outdated) &&
          !(author != null &&
              author.isNotEmpty &&
              thread.every(
                (comment) =>
                    (comment.author ?? '').trim().toLowerCase() == author,
              )))
        PendingReviewThread(
          id: id,
          path: thread.first.path,
          line: thread.first.line,
        ),
  ];
}

/// `unknown` mergeability is not a conflict: GitHub recomputes it after every
/// push, so treating it as one would dispatch on each new commit.
PullRequestAgentWatchConcerns pullRequestAgentWatchConcerns({
  required PullRequestAgentWatchSnapshot snapshot,
  required PullRequestAgentWatchScope scope,
}) {
  final review = snapshot.review;
  return PullRequestAgentWatchConcerns(
    checksFailed:
        scope.checks &&
        snapshot.checksRollup == PullRequestChecksRollup.failure,
    conflict:
        scope.conflicts && review?.mergeable?.toUpperCase() == 'CONFLICTING',
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
  String? error,
}) {
  if (result == null) {
    return error == null ? session : session.copyWith(lastError: error);
  }
  return session.copyWith(
    binding: result.binding,
    lastDispatch: pullRequestAgentWatchDispatchMark(
      previous: session.lastDispatch,
      headSha: headSha,
      concerns: concerns,
    ),
    clearError: true,
  );
}

/// Keep the watch eligible to retry when the forge merge did not succeed.
PullRequestAgentWatchSession pullRequestAgentWatchAfterMerge({
  required PullRequestAgentWatchSession session,
  required bool merged,
  required String? headSha,
  String? error,
}) {
  if (!merged) {
    return error == null ? session : session.copyWith(lastError: error);
  }
  return session.copyWith(lastMergedHeadSha: headSha, clearError: true);
}

PullRequestAgentWatchSnapshot pullRequestAgentWatchSnapshotFrom(
  MobilePullRequestSnapshot snapshot,
) {
  final review = snapshot.review;
  return PullRequestAgentWatchSnapshot(
    loaded: true,
    review: review,
    checksRollup: derivePullRequestChecksRollup(
      review?.checks ?? const <MobilePullRequestCheck>[],
    ),
    comments: review?.comments ?? const <MobilePullRequestComment>[],
    commentsComplete: review == null || !review.commentsTruncated,
  );
}

PullRequestAgentWatchEvaluation evaluatePullRequestAgentWatch({
  required PullRequestAgentWatchSession session,
  required PullRequestAgentWatchSnapshot? snapshot,
}) {
  if (snapshot == null || !snapshot.loaded) {
    return const PullRequestAgentWatchEvaluation(
      action: PullRequestAgentWatchAction.none,
    );
  }
  final review = snapshot.review;
  if (review == null || review.number != session.reviewNumber) {
    return const PullRequestAgentWatchEvaluation(
      action: PullRequestAgentWatchAction.stop,
    );
  }
  final state = review.state.toUpperCase();
  if (state == 'MERGED' || state == 'CLOSED') {
    return const PullRequestAgentWatchEvaluation(
      action: PullRequestAgentWatchAction.stop,
    );
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
      action: PullRequestAgentWatchAction.dispatch,
      concerns: concerns,
      headSha: headSha,
    );
  }
  if (session.mode == PullRequestAgentWatchMode.fixAndMerge &&
      (!session.watchScope.comments || snapshot.commentsComplete) &&
      snapshot.checksRollup == PullRequestChecksRollup.success &&
      state == 'OPEN' &&
      !review.isDraft &&
      review.mergeable?.toUpperCase() == 'MERGEABLE' &&
      concerns.threads.isEmpty &&
      headSha != null &&
      headSha.isNotEmpty &&
      headSha != session.lastMergedHeadSha) {
    return PullRequestAgentWatchEvaluation(
      action: PullRequestAgentWatchAction.merge,
      headSha: headSha,
    );
  }
  return PullRequestAgentWatchEvaluation(
    action: PullRequestAgentWatchAction.none,
    concerns: concerns,
    headSha: headSha,
  );
}
