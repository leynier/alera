import 'package:alera/src/features/pull_requests/domain/review_comment.dart';

/// One entry of the pull-request conversation timeline.
sealed class const ReviewConversationEntry() {
  DateTime get createdAt;
}

/// A top-level conversation comment or review summary.
final class const ReviewConversationComment(final ReviewComment comment)
    extends ReviewConversationEntry {
  @override
  DateTime get createdAt => comment.createdAt;
}

/// Review comments that share one diff thread, oldest first. Never empty.
final class const ReviewConversationThread({
  required final String id,
  required final List<ReviewComment> comments,
}) extends ReviewConversationEntry {
  @override
  DateTime get createdAt => comments.first.createdAt;

  String? get path => comments.first.path;

  int? get line => comments.first.line;

  /// Providers report resolution per thread, so one flagged comment is enough.
  bool get resolved => comments.any((comment) => comment.resolved);

  /// `path:line`, the bare path, or null when the thread has no file.
  String? get location {
    final path = this.path;
    if (path == null || path.isEmpty) {
      return null;
    }
    return line == null ? path : '$path:$line';
  }
}

/// The pull-request conversation as a timeline of comments and diff threads.
final class const ReviewConversation({
  required final List<ReviewConversationEntry> entries,
}) {
  bool get isEmpty => entries.isEmpty;

  int get commentCount => entries.fold(
    0,
    (total, entry) => switch (entry) {
      ReviewConversationComment() => total + 1,
      ReviewConversationThread(:final comments) => total + comments.length,
    },
  );

  int get unresolvedThreadCount => entries
      .whereType<ReviewConversationThread>()
      .where((thread) => !thread.resolved)
      .length;
}

/// Groups review comments into their diff threads and orders every entry by
/// its first comment. A review comment without a thread id (a provider that
/// does not report one) becomes a thread of its own.
ReviewConversation buildReviewConversation(List<ReviewComment> comments) {
  final indexed = <(int, ReviewComment)>[
    for (var index = 0; index < comments.length; index++)
      (index, comments[index]),
  ];
  // List.sort is not stable, so the original index breaks createdAt ties.
  indexed.sort((a, b) {
    final byTime = a.$2.createdAt.compareTo(b.$2.createdAt);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  final slots = <Object>[];
  final threads = <String, List<ReviewComment>>{};
  for (final (_, comment) in indexed) {
    if (comment.kind != ReviewCommentKind.review) {
      slots.add(comment);
      continue;
    }
    final key = comment.threadId ?? comment.id;
    final existing = threads[key];
    if (existing != null) {
      existing.add(comment);
      continue;
    }
    threads[key] = <ReviewComment>[comment];
    slots.add(key);
  }
  return ReviewConversation(
    entries: List<ReviewConversationEntry>.unmodifiableOf(
      <ReviewConversationEntry>[
        for (final slot in slots)
          switch (slot) {
            ReviewComment() => ReviewConversationComment(slot),
            _ => ReviewConversationThread(
              id: slot as String,
              comments: List<ReviewComment>.unmodifiableOf(threads[slot]!),
            ),
          },
      ],
    ),
  );
}
