import 'package:alera/src/features/pull_requests/domain/review_comment.dart';

/// A review thread that still asks for a change.
class const PendingReviewThread({
  required final String id,
  final String? path,
  final int? line,
});

/// Groups [comments] into threads and keeps the ones an agent should address.
///
/// Only comments with a thread id count: loose conversation comments cannot
/// be resolved, so counting them would keep a watch dispatching forever. A
/// thread is dropped when it is resolved, when every comment in it is outdated,
/// or when [reviewAuthor] wrote all of it, because a note the author left for
/// themselves is not review feedback. GitLab and Azure DevOps expose no
/// outdated state, so their threads never drop for that reason.
List<PendingReviewThread> pendingReviewThreads({
  required List<ReviewComment> comments,
  String? reviewAuthor,
}) {
  final threads = <String, List<ReviewComment>>{};
  for (final comment in comments) {
    final threadId = comment.locator?.parentId;
    if (threadId == null || threadId.isEmpty) {
      continue;
    }
    (threads[threadId] ??= <ReviewComment>[]).add(comment);
  }
  final author = reviewAuthor?.trim().toLowerCase();
  return <PendingReviewThread>[
    for (final MapEntry(key: id, value: thread) in threads.entries)
      if (!thread.any((comment) => comment.resolved) &&
          !thread.every((comment) => comment.outdated) &&
          !(author != null &&
              author.isNotEmpty &&
              thread.every(
                (comment) => comment.author.trim().toLowerCase() == author,
              )))
        PendingReviewThread(
          id: id,
          path: thread.first.path,
          line: thread.first.line,
        ),
  ];
}
