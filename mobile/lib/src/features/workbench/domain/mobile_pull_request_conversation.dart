import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';

// Mirrors the desktop conversation model
// (lib/src/features/pull_requests/domain/review_conversation.dart and
// comment_relative_time.dart). alera_mobile cannot import the root package,
// so keep both copies in sync.

/// One entry of the pull-request conversation timeline.
sealed class const MobilePullRequestConversationEntry();

/// A top-level conversation comment or review summary.
final class const MobilePullRequestConversationComment(
  final MobilePullRequestComment comment,
) extends MobilePullRequestConversationEntry;

/// Review comments that share one diff thread, oldest first. Never empty.
final class const MobilePullRequestConversationThread({
  required final String id,
  required final List<MobilePullRequestComment> comments,
}) extends MobilePullRequestConversationEntry {
  /// Providers report resolution per thread, so one flagged comment is enough.
  bool get resolved => comments.any((comment) => comment.resolved);

  /// `path:line`, the bare path, or null when the thread has no file.
  String? get location {
    final path = comments.first.path;
    if (path == null || path.isEmpty) {
      return null;
    }
    final line = comments.first.line;
    return line == null ? path : '$path:$line';
  }
}

/// The pull-request conversation as a timeline of comments and diff threads.
final class const MobilePullRequestConversation({
  required final List<MobilePullRequestConversationEntry> entries,
}) {
  bool get isEmpty => entries.isEmpty;

  int get commentCount => entries.fold(
    0,
    (total, entry) => switch (entry) {
      MobilePullRequestConversationComment() => total + 1,
      MobilePullRequestConversationThread(:final comments) =>
        total + comments.length,
    },
  );

  int get unresolvedThreadCount => entries
      .whereType<MobilePullRequestConversationThread>()
      .where((thread) => !thread.resolved)
      .length;
}

final DateTime _unknownTime = DateTime.fromMillisecondsSinceEpoch(
  0,
  isUtc: true,
);

/// Groups review comments into their diff threads and orders every entry by
/// its first comment. A review comment without a thread id becomes a thread
/// of its own; a comment without a timestamp sorts first.
MobilePullRequestConversation buildMobilePullRequestConversation(
  List<MobilePullRequestComment> comments,
) {
  final indexed = <(int, MobilePullRequestComment)>[
    for (var index = 0; index < comments.length; index++)
      (index, comments[index]),
  ];
  // List.sort is not stable, so the original index breaks createdAt ties.
  indexed.sort((a, b) {
    final byTime = (a.$2.createdAtTime ?? _unknownTime).compareTo(
      b.$2.createdAtTime ?? _unknownTime,
    );
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  final slots = <Object>[];
  final threads = <String, List<MobilePullRequestComment>>{};
  for (final (_, comment) in indexed) {
    if (!comment.isReviewThread) {
      slots.add(comment);
      continue;
    }
    final key = comment.threadId ?? 'comment:${comment.id}';
    final existing = threads[key];
    if (existing != null) {
      existing.add(comment);
      continue;
    }
    threads[key] = <MobilePullRequestComment>[comment];
    slots.add(key);
  }
  return MobilePullRequestConversation(
    entries: List<MobilePullRequestConversationEntry>.unmodifiableOf(
      <MobilePullRequestConversationEntry>[
        for (final slot in slots)
          switch (slot) {
            MobilePullRequestComment() => MobilePullRequestConversationComment(
              slot,
            ),
            _ => MobilePullRequestConversationThread(
              id: slot as String,
              comments: List<MobilePullRequestComment>.unmodifiableOf(
                threads[slot]!,
              ),
            ),
          },
      ],
    ),
  );
}

/// Compact age of a comment relative to [now], or null once it is a week old,
/// where a calendar date reads better than a count. A timestamp in the future
/// (clock skew) reads as `just now`.
String? pullRequestCommentRelativeTimeLabel(DateTime value, DateTime now) {
  final age = now.difference(value);
  if (age < const Duration(minutes: 1)) {
    return 'just now';
  }
  if (age < const Duration(hours: 1)) {
    return '${age.inMinutes}m ago';
  }
  if (age < const Duration(days: 1)) {
    return '${age.inHours}h ago';
  }
  if (age < const Duration(days: 7)) {
    return '${age.inDays}d ago';
  }
  return null;
}
