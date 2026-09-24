import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_conversation.dart';
import 'package:flutter/material.dart';

final DateTime _now = DateTime.utc(2026, 9, 12, 12);

final List<ReviewComment> _comments = <ReviewComment>[
  ReviewComment(
    id: 'issue:1',
    author: 'alice',
    body: 'Thanks for picking this up. Can we keep the **old endpoint** too?',
    createdAt: _now.subtract(const Duration(hours: 5)),
    kind: .conversation,
    url: 'https://github.com/leynier/alera/pull/1#issuecomment-1',
  ),
  ReviewComment(
    id: 'thread:T1:2',
    author: 'bob',
    body: 'This loop runs on the main isolate.',
    createdAt: _now.subtract(const Duration(hours: 3)),
    kind: .review,
    path: 'lib/src/example.dart',
    line: 42,
    threadId: 'T1',
  ),
  ReviewComment(
    id: 'thread:T1:3',
    author: 'alice',
    body: 'Moved it behind `compute`.',
    createdAt: _now.subtract(const Duration(minutes: 20)),
    kind: .review,
    path: 'lib/src/example.dart',
    line: 42,
    threadId: 'T1',
  ),
  ReviewComment(
    id: 'thread:T2:4',
    author: 'bob',
    body: 'Typo in the doc comment.',
    createdAt: _now.subtract(const Duration(hours: 2)),
    kind: .review,
    path: 'README.md',
    line: 7,
    resolved: true,
    threadId: 'T2',
  ),
  ReviewComment(
    id: 'review:5',
    author: 'carol',
    body: 'Looks good once the thread above is settled.',
    createdAt: _now.subtract(const Duration(days: 9)),
    kind: .conversation,
    locator: const ReviewCommentLocator(source: .reviewSummary, commentId: '5'),
  ),
];

Widget _frame(List<ReviewComment> comments) => SizedBox(
  width: 360,
  child: SingleChildScrollView(
    child: PullRequestConversation(
      comments: comments,
      canComment: true,
      onAddComment: (_) async => true,
      onToggleTask: (_, _) async {},
      onOpenUrl: (_) async {},
      now: _now,
    ),
  ),
);

@AleraPreview(name: 'Conversation', group: 'PR comments')
Widget pullRequestConversationPreview() => _frame(_comments);

@AleraPreview(name: 'Empty conversation', group: 'PR comments')
Widget pullRequestConversationEmptyPreview() => _frame(const <ReviewComment>[]);
