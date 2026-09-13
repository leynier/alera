import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 12, 12);

class _Recorder {
  final List<String> openedUrls = <String>[];
  final List<String> posted = <String>[];
  bool accept = true;
}

Widget _wrap(
  _Recorder recorder,
  List<ReviewComment> comments, {
  bool canComment = true,
  bool busy = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PullRequestConversation(
          comments: comments,
          canComment: canComment,
          busy: busy,
          onAddComment: (body) async {
            recorder.posted.add(body);
            return recorder.accept;
          },
          onToggleTask: (_, _) async {},
          onOpenUrl: (url) async => recorder.openedUrls.add(url),
          now: _now,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows relative time, review tags, and opens the forge link', (
    tester,
  ) async {
    final recorder = _Recorder();
    await tester.pumpWidget(
      _wrap(recorder, <ReviewComment>[
        ReviewComment(
          id: 'issue:1',
          author: 'alice',
          body: 'General feedback',
          createdAt: _now.subtract(const Duration(minutes: 5)),
          kind: .conversation,
          url: 'https://github.com/leynier/alera/pull/1#issuecomment-1',
        ),
        ReviewComment(
          id: 'review:2',
          author: 'carol',
          body: 'Approved',
          createdAt: _now.subtract(const Duration(days: 2)),
          kind: .conversation,
          locator: const ReviewCommentLocator(
            source: .reviewSummary,
            commentId: '2',
          ),
        ),
      ]),
    );

    expect(find.text('5m ago'), findsOneWidget);
    expect(find.text('2d ago'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.byTooltip('Open Comment'), findsOneWidget);

    await tester.tap(find.byTooltip('Open Comment'));
    await tester.pump();

    expect(recorder.openedUrls, <String>[
      'https://github.com/leynier/alera/pull/1#issuecomment-1',
    ]);
  });

  testWidgets('falls back to a calendar date after a week', (tester) async {
    await tester.pumpWidget(
      _wrap(_Recorder(), <ReviewComment>[
        ReviewComment(
          id: 'issue:1',
          author: 'alice',
          body: 'Old note',
          createdAt: .utc(2026, 7, 16, 12),
          kind: .conversation,
        ),
        ReviewComment(
          id: 'issue:2',
          author: 'bob',
          body: 'Older note',
          createdAt: .utc(2025, 3, 4, 12),
          kind: .conversation,
        ),
      ]),
    );

    expect(find.textContaining('ago'), findsNothing);
    expect(find.text('Jul 16'), findsOneWidget);
    // Another year keeps the year in the label.
    expect(find.textContaining('2025'), findsOneWidget);
    // The time of day depends on the machine's zone; the full date does not.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message ?? '').startsWith('Thursday, July 16, 2026 · '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('groups a thread and counts its unresolved state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_Recorder(), <ReviewComment>[
        for (final (index, author) in <String>['bob', 'alice'].indexed)
          ReviewComment(
            id: 'thread:T1:$index',
            author: author,
            body: 'Thread note $index',
            createdAt: _now.subtract(Duration(hours: 3 - index)),
            kind: .review,
            path: 'lib/a.dart',
            line: 7,
            threadId: 'T1',
          ),
      ]),
    );

    expect(find.text('Comments (2)'), findsOneWidget);
    expect(find.text('1 unresolved'), findsOneWidget);
    expect(find.text('lib/a.dart:7'), findsOneWidget);
    expect(find.text('Thread note 0'), findsOneWidget);
    expect(find.text('Thread note 1'), findsOneWidget);
    expect(find.text('Resolved'), findsNothing);
  });

  testWidgets('the composer posts only a non-empty draft', (tester) async {
    final recorder = _Recorder();
    await tester.pumpWidget(_wrap(recorder, const <ReviewComment>[]));

    expect(find.text('No comments yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Start the conversation'));
    await tester.pumpAndSettle();

    FilledButton post() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Post Comment'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(post().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(post().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.pump();
    await tester.tap(find.text('Post Comment'));
    await tester.pumpAndSettle();

    expect(recorder.posted, <String>['Ship it']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('cancel discards the draft and collapses the composer', (
    tester,
  ) async {
    final recorder = _Recorder();
    await tester.pumpWidget(_wrap(recorder, const <ReviewComment>[]));

    await tester.tap(find.text('Start the conversation'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(recorder.posted, isEmpty);

    await tester.tap(find.text('Start the conversation'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('a busy panel does not open the composer', (tester) async {
    await tester.pumpWidget(
      _wrap(_Recorder(), const <ReviewComment>[], busy: true),
    );

    await tester.tap(find.text('Start the conversation'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('hides the composer when commenting is not allowed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_Recorder(), const <ReviewComment>[], canComment: false),
    );

    expect(find.text('Start the conversation'), findsNothing);
    expect(find.text('Add a comment'), findsNothing);
  });

  testWidgets('keeps an expanded resolved thread open across refreshes', (
    tester,
  ) async {
    final recorder = _Recorder();
    List<ReviewComment> comments(String body) => <ReviewComment>[
      ReviewComment(
        id: 'thread:T1:1',
        author: 'bob',
        body: body,
        createdAt: _now.subtract(const Duration(hours: 1)),
        kind: .review,
        path: 'lib/a.dart',
        resolved: true,
        threadId: 'T1',
      ),
    ];
    await tester.pumpWidget(_wrap(recorder, comments('First')));

    expect(find.text('Add a comment'), findsOneWidget);
    await tester.tap(find.text('lib/a.dart'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    await tester.pumpWidget(_wrap(recorder, comments('Edited')));
    await tester.pumpAndSettle();

    expect(find.text('Edited'), findsOneWidget);
  });
}
