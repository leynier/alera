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
}) {
  factory fromJson(Map<String, Object?> json) {
    final threadIds = json['threadIds'];
    return PullRequestAgentWatchDispatchMark(
      headSha: json['headSha'] as String?,
      checksFailed: json['checksFailed'] == true,
      conflict: json['conflict'] == true,
      threadIds: <String>{
        if (threadIds is List)
          for (final id in threadIds)
            if (id is String && id.isNotEmpty) id,
      },
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'headSha': headSha,
    'checksFailed': checksFailed,
    'conflict': conflict,
    'threadIds': threadIds.toList(growable: false)..sort(),
  };
}

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

String pullRequestAgentWatchModeToJson(PullRequestAgentWatchMode mode) {
  return switch (mode) {
    PullRequestAgentWatchMode.fix => 'fix',
    PullRequestAgentWatchMode.fixAndMerge => 'fixAndMerge',
  };
}

PullRequestAgentWatchMode pullRequestAgentWatchModeFromJson(String? value) {
  return value == 'fixAndMerge'
      ? PullRequestAgentWatchMode.fixAndMerge
      : PullRequestAgentWatchMode.fix;
}

/// Sidebar tooltip for an active watch: mode plus each scope toggle.
String pullRequestAgentWatchTooltip({
  required PullRequestAgentWatchMode mode,
  required PullRequestAgentWatchScope scope,
}) {
  String line(String label, bool enabled) =>
      '$label: ${enabled ? 'On' : 'Off'}';
  return <String>[
    pullRequestAgentWatchModeLabel(mode),
    line('Failed Checks', scope.checks),
    line('Review Comments', scope.comments),
    line('Merge Conflicts', scope.conflicts),
  ].join('\n');
}

/// Host-persisted watch session. Desktop reconstructs [WorkspacePullRequestScope]
/// from the live workspace; the host does not store repo paths.
class const PullRequestAgentWatchRecord({
  required this.workspaceId,
  required this.reviewNumber,
  required this.mode,
  this.watchScope = PullRequestAgentWatchScope.defaults,
  this.tabId,
  this.profileId,
  this.label,
  this.lastDispatch,
  this.lastMergedHeadSha,
}) {
  final String workspaceId;
  final int reviewNumber;
  final PullRequestAgentWatchMode mode;
  final PullRequestAgentWatchScope watchScope;
  final String? tabId;
  final String? profileId;
  final String? label;
  final PullRequestAgentWatchDispatchMark? lastDispatch;
  final String? lastMergedHeadSha;

  AgentTaskDispatchBinding get binding => AgentTaskDispatchBinding(
    tabId: tabId,
    profileId: profileId,
    label: label,
  );

  factory fromSession(PullRequestAgentWatchSession session) {
    return PullRequestAgentWatchRecord(
      workspaceId: session.workspaceId,
      reviewNumber: session.reviewNumber,
      mode: session.mode,
      watchScope: session.watchScope,
      tabId: session.binding.tabId,
      profileId: session.binding.profileId,
      label: session.binding.label,
      lastDispatch: session.lastDispatch,
      lastMergedHeadSha: session.lastMergedHeadSha,
    );
  }

  factory fromJson(Map<String, Object?> json) {
    final lastDispatch = json['lastDispatch'];
    return PullRequestAgentWatchRecord(
      workspaceId: json['workspaceId'] as String? ?? '',
      reviewNumber: (json['reviewNumber'] as num?)?.toInt() ?? 0,
      mode: pullRequestAgentWatchModeFromJson(json['mode'] as String?),
      watchScope: PullRequestAgentWatchScope(
        checks: json['checks'] != false,
        comments: json['comments'] != false,
        conflicts: json['conflicts'] != false,
      ),
      tabId: json['tabId'] as String?,
      profileId: json['profileId'] as String?,
      label: json['label'] as String?,
      lastDispatch: lastDispatch is Map
          ? PullRequestAgentWatchDispatchMark.fromJson(
              Map<String, Object?>.from(lastDispatch),
            )
          : null,
      lastMergedHeadSha: json['lastMergedHeadSha'] as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'reviewNumber': reviewNumber,
    'mode': pullRequestAgentWatchModeToJson(mode),
    'checks': watchScope.checks,
    'comments': watchScope.comments,
    'conflicts': watchScope.conflicts,
    'tabId': tabId,
    'profileId': profileId,
    'label': label,
    'lastDispatch': lastDispatch?.toJson(),
    'lastMergedHeadSha': lastMergedHeadSha,
  };
}

class const PullRequestAgentWatchRecords({
  this.supported = false,
  this.byWorkspace = const <String, PullRequestAgentWatchRecord>{},
}) {
  final bool supported;
  final Map<String, PullRequestAgentWatchRecord> byWorkspace;
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
      (!session.watchScope.comments || snapshot.commentsComplete) &&
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
