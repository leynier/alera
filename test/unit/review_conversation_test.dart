import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_conversation.dart';
import 'package:flutter_test/flutter_test.dart';

ReviewComment _comment(
  String id, {
  required int hour,
  ReviewCommentKind kind = .conversation,
  String? threadId,
  String? path,
  int? line,
  bool resolved = false,
}) {
  return ReviewComment(
    id: id,
    author: 'alice',
    body: 'body $id',
    createdAt: DateTime.utc(2026, 9, 12, hour),
    kind: kind,
    threadId: threadId,
    path: path,
    line: line,
    resolved: resolved,
  );
}

void main() {
  test('an empty list is an empty conversation', () {
    final conversation = buildReviewConversation(const <ReviewComment>[]);

    expect(conversation.isEmpty, isTrue);
    expect(conversation.commentCount, 0);
    expect(conversation.unresolvedThreadCount, 0);
  });

  test('groups review comments by thread and orders by first comment', () {
    final conversation = buildReviewConversation(<ReviewComment>[
      _comment('general', hour: 11),
      _comment(
        'reply',
        hour: 13,
        kind: .review,
        threadId: 'T1',
        path: 'a.dart',
        line: 4,
      ),
      _comment(
        'first',
        hour: 10,
        kind: .review,
        threadId: 'T1',
        path: 'a.dart',
        line: 4,
      ),
      _comment('later', hour: 12),
    ]);

    expect(conversation.isEmpty, isFalse);
    expect(conversation.commentCount, 4);
    final entries = conversation.entries;
    expect(entries, hasLength(3));
    final thread = entries[0] as ReviewConversationThread;
    expect(thread.id, 'T1');
    expect(thread.comments.map((comment) => comment.id), <String>[
      'first',
      'reply',
    ]);
    expect(thread.createdAt, DateTime.utc(2026, 9, 12, 10));
    expect(thread.location, 'a.dart:4');
    expect((entries[1] as ReviewConversationComment).comment.id, 'general');
    expect(entries[1].createdAt, DateTime.utc(2026, 9, 12, 11));
    expect((entries[2] as ReviewConversationComment).comment.id, 'later');
  });

  test('a review comment without a thread id becomes its own thread', () {
    final conversation = buildReviewConversation(<ReviewComment>[
      _comment('a', hour: 10, kind: .review, path: 'a.dart'),
      _comment('b', hour: 11, kind: .review, path: 'a.dart'),
    ]);

    final ids = conversation.entries.cast<ReviewConversationThread>().map(
      (thread) => thread.id,
    );
    expect(ids, <String>['a', 'b']);
    expect(conversation.entries.first, isA<ReviewConversationThread>());
  });

  test('keeps input order for comments created at the same time', () {
    final conversation = buildReviewConversation(<ReviewComment>[
      for (var index = 0; index < 20; index++) _comment('c$index', hour: 10),
    ]);

    expect(
      conversation.entries.map(
        (entry) => (entry as ReviewConversationComment).comment.id,
      ),
      <String>[for (var index = 0; index < 20; index++) 'c$index'],
    );
  });

  test('counts unresolved threads and exposes thread resolution', () {
    final conversation = buildReviewConversation(<ReviewComment>[
      _comment('open', hour: 10, kind: .review, threadId: 'T1'),
      _comment('done', hour: 11, kind: .review, threadId: 'T2', resolved: true),
      _comment('done-reply', hour: 12, kind: .review, threadId: 'T2'),
    ]);

    final threads = conversation.entries
        .cast<ReviewConversationThread>()
        .toList();
    expect(threads[0].resolved, isFalse);
    expect(threads[1].resolved, isTrue);
    expect(conversation.unresolvedThreadCount, 1);
  });

  test('describes the thread location from path and line', () {
    ReviewConversationThread thread({String? path, int? line}) =>
        ReviewConversationThread(
          id: 'T',
          comments: <ReviewComment>[
            _comment('x', hour: 10, kind: .review, path: path, line: line),
          ],
        );

    expect(thread(path: 'lib/a.dart', line: 9).location, 'lib/a.dart:9');
    expect(thread(path: 'lib/a.dart').location, 'lib/a.dart');
    expect(thread(path: '').location, isNull);
    expect(thread().location, isNull);
    expect(thread(path: 'lib/a.dart', line: 9).path, 'lib/a.dart');
    expect(thread(path: 'lib/a.dart', line: 9).line, 9);
  });

  test('the grouped lists cannot be mutated', () {
    final conversation = buildReviewConversation(<ReviewComment>[
      _comment('a', hour: 10, kind: .review, threadId: 'T1'),
    ]);

    expect(() => conversation.entries.clear(), throwsUnsupportedError);
    expect(
      () => (conversation.entries.single as ReviewConversationThread).comments
          .clear(),
      throwsUnsupportedError,
    );
  });
}
