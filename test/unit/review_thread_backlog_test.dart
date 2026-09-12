import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_thread_backlog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pendingReviewThreads', () {
    test('groups comments by thread and keeps the first location', () {
      final threads = pendingReviewThreads(
        comments: <ReviewComment>[
          _comment('T1', author: 'pullfrog', path: 'lib/a.dart', line: 3),
          _comment('T1', author: 'leynier', path: 'lib/a.dart', line: 3),
          _comment('T2', author: 'pullfrog', path: 'lib/b.dart', line: 9),
        ],
        reviewAuthor: 'leynier',
      );

      expect(threads.map((thread) => thread.id), <String>['T1', 'T2']);
      expect(threads.first.path, 'lib/a.dart');
      expect(threads.first.line, 3);
    });

    test('ignores comments that belong to no thread', () {
      final threads = pendingReviewThreads(
        comments: <ReviewComment>[
          _comment(null, author: 'alice'),
          _comment('', author: 'alice'),
        ],
      );

      expect(threads, isEmpty);
    });

    test('drops resolved threads', () {
      final threads = pendingReviewThreads(
        comments: <ReviewComment>[
          _comment('T1', author: 'alice', resolved: true),
          _comment('T1', author: 'bob', resolved: true),
        ],
      );

      expect(threads, isEmpty);
    });

    test('drops a thread only when every comment is outdated', () {
      final threads = pendingReviewThreads(
        comments: <ReviewComment>[
          _comment('T1', author: 'alice', outdated: true),
          _comment('T2', author: 'alice', outdated: true),
          _comment('T2', author: 'bob'),
        ],
      );

      expect(threads.map((thread) => thread.id), <String>['T2']);
    });

    test('drops threads written only by the pull request author', () {
      final threads = pendingReviewThreads(
        comments: <ReviewComment>[
          _comment('T1', author: 'Leynier'),
          _comment('T1', author: 'leynier'),
          _comment('T2', author: 'leynier'),
          _comment('T2', author: 'pullfrog'),
        ],
        reviewAuthor: 'leynier',
      );

      expect(threads.map((thread) => thread.id), <String>['T2']);
    });

    test('keeps author threads when the author is unknown', () {
      final threads = pendingReviewThreads(
        comments: <ReviewComment>[_comment('T1', author: 'leynier')],
      );

      expect(threads.map((thread) => thread.id), <String>['T1']);
    });
  });
}

ReviewComment _comment(
  String? threadId, {
  required String author,
  String? path,
  int? line,
  bool resolved = false,
  bool outdated = false,
}) {
  return ReviewComment(
    id: 'thread:$threadId:$author',
    author: author,
    body: 'Please change this.',
    createdAt: DateTime.utc(2026, 9, 12),
    kind: threadId == null ? .conversation : .review,
    path: path,
    line: line,
    resolved: resolved,
    outdated: outdated,
    locator: ReviewCommentLocator(
      source: threadId == null ? .conversation : .reviewThread,
      commentId: author,
      parentId: threadId,
    ),
  );
}
