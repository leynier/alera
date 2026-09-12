import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_pull_request_conversation.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_conversation_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 9, 12, 12);

String _at(Duration age) => _now.subtract(age).toIso8601String();

MobilePullRequestComment _comment(
  int id, {
  required Duration age,
  String kind = 'conversation',
  String source = 'conversation',
  String? threadId,
  String? path,
  int? line,
  bool resolved = false,
  String? url,
  String body = 'body',
}) {
  return MobilePullRequestComment(
    id: id,
    author: 'user$id',
    body: body,
    createdAt: _at(age),
    kind: kind,
    source: source,
    threadId: threadId,
    path: path,
    line: line,
    resolved: resolved,
    url: url,
  );
}

void main() {
  group('MobilePullRequestComment', () {
    test('parses review thread fields', () {
      final comment = MobilePullRequestComment.fromJson(const <String, Object?>{
        'id': 2,
        'author': 'bob',
        'body': 'Change this',
        'createdAt': '2026-07-16T11:00:00Z',
        'kind': 'review',
        'source': 'reviewThread',
        'path': 'lib/a.dart',
        'line': 17,
        'resolved': true,
        'threadId': 'T1',
      });

      expect(comment.isReviewThread, isTrue);
      expect(comment.isReviewSummary, isFalse);
      expect(comment.path, 'lib/a.dart');
      expect(comment.line, 17);
      expect(comment.resolved, isTrue);
      expect(comment.threadId, 'T1');
      expect(comment.createdAtTime, DateTime.utc(2026, 7, 16, 11));
    });

    test('an older host payload reads as a conversation comment', () {
      final comment = MobilePullRequestComment.fromJson(const <String, Object?>{
        'id': 1,
        'author': 'reviewer',
        'body': 'Looks good',
      });

      expect(comment.isReviewThread, isFalse);
      expect(comment.isReviewSummary, isFalse);
      expect(comment.resolved, isFalse);
      expect(comment.threadId, isNull);
      expect(comment.createdAtTime, isNull);
      expect(
        MobilePullRequestComment.fromJson(const <String, Object?>{
          'id': 3,
          'source': 'reviewSummary',
          'createdAt': 'not a date',
        }),
        isA<MobilePullRequestComment>()
            .having((c) => c.isReviewSummary, 'isReviewSummary', isTrue)
            .having((c) => c.createdAtTime, 'createdAtTime', isNull),
      );
    });
  });

  group('buildMobilePullRequestConversation', () {
    test('groups threads, keeps order, and counts', () {
      final conversation = buildMobilePullRequestConversation(
        <MobilePullRequestComment>[
          _comment(1, age: const Duration(hours: 2)),
          _comment(
            3,
            age: const Duration(minutes: 30),
            kind: 'review',
            threadId: 'T1',
            path: 'a.dart',
            line: 4,
          ),
          _comment(
            2,
            age: const Duration(hours: 3),
            kind: 'review',
            threadId: 'T1',
            path: 'a.dart',
            line: 4,
          ),
          _comment(
            4,
            age: const Duration(hours: 1),
            kind: 'review',
            path: 'b.dart',
            resolved: true,
          ),
          const MobilePullRequestComment(id: 5, body: 'undated'),
        ],
      );

      expect(conversation.isEmpty, isFalse);
      expect(conversation.commentCount, 5);
      expect(conversation.unresolvedThreadCount, 1);
      final entries = conversation.entries;
      expect(
        (entries[0] as MobilePullRequestConversationComment).comment.id,
        5,
      );
      final thread = entries[1] as MobilePullRequestConversationThread;
      expect(thread.id, 'T1');
      expect(thread.comments.map((comment) => comment.id), <int>[2, 3]);
      expect(thread.location, 'a.dart:4');
      expect(thread.resolved, isFalse);
      expect(
        (entries[2] as MobilePullRequestConversationComment).comment.id,
        1,
      );
      final lone = entries[3] as MobilePullRequestConversationThread;
      expect(lone.id, 'comment:4');
      expect(lone.location, 'b.dart');
      expect(lone.resolved, isTrue);
    });

    test('keeps input order for simultaneous comments', () {
      final conversation = buildMobilePullRequestConversation(
        <MobilePullRequestComment>[
          for (var id = 0; id < 20; id++) _comment(id, age: Duration.zero),
        ],
      );

      expect(
        conversation.entries.map(
          (entry) => (entry as MobilePullRequestConversationComment).comment.id,
        ),
        <int>[for (var id = 0; id < 20; id++) id],
      );
    });

    test('an empty list is empty and a pathless thread has no location', () {
      expect(
        buildMobilePullRequestConversation(const <MobilePullRequestComment>[])
            .isEmpty,
        isTrue,
      );
      final thread = MobilePullRequestConversationThread(
        id: 'T',
        comments: <MobilePullRequestComment>[
          _comment(1, age: Duration.zero, kind: 'review', path: ''),
        ],
      );
      expect(thread.location, isNull);
    });
  });

  test('relative time labels', () {
    String? label(Duration age) =>
        pullRequestCommentRelativeTimeLabel(_now.subtract(age), _now);

    expect(label(const Duration(seconds: 59)), 'just now');
    expect(label(const Duration(minutes: -5)), 'just now');
    expect(label(const Duration(minutes: 1)), '1m ago');
    expect(label(const Duration(minutes: 60)), '1h ago');
    expect(label(const Duration(hours: 24)), '1d ago');
    expect(label(const Duration(days: 6, hours: 23)), '6d ago');
    expect(label(const Duration(days: 7)), isNull);
  });

  group('PullRequestConversationSection', () {
    Future<List<Uri>> pump(
      WidgetTester tester,
      List<MobilePullRequestComment> comments,
    ) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAleraMobileDarkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PullRequestConversationSection(
                comments: comments,
                now: _now,
                openUrl: (url) async {
                  opened.add(url);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('renders Markdown, time, count, and the forge link', (
      tester,
    ) async {
      final opened = await pump(tester, <MobilePullRequestComment>[
        _comment(
          1,
          age: const Duration(minutes: 5),
          body: 'Please keep the **old endpoint**',
          url: 'https://github.com/leynier/alera/pull/1#issuecomment-1',
        ),
        _comment(
          2,
          age: const Duration(days: 30),
          source: 'reviewSummary',
          body: 'Approved',
        ),
      ]);

      expect(find.text('COMMENTS'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('5m ago'), findsOneWidget);
      expect(find.text('Aug 13'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(
        find.textContaining('old endpoint', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('**', findRichText: true), findsNothing);

      await tester.tap(find.byTooltip('Open Comment'));
      await tester.pump();

      expect(opened, <Uri>[
        Uri.parse('https://github.com/leynier/alera/pull/1#issuecomment-1'),
      ]);
    });

    testWidgets('collapses resolved threads until tapped', (tester) async {
      await pump(tester, <MobilePullRequestComment>[
        _comment(
          1,
          age: const Duration(hours: 2),
          kind: 'review',
          threadId: 'T1',
          path: 'lib/a.dart',
          line: 9,
          body: 'Resolved note',
          resolved: true,
        ),
        _comment(
          2,
          age: const Duration(hours: 1),
          kind: 'review',
          threadId: 'T2',
          path: 'lib/b.dart',
          body: 'Open note',
        ),
      ]);

      expect(find.text('1 unresolved'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('lib/a.dart:9'), findsOneWidget);
      expect(find.text('1 comment'), findsOneWidget);
      expect(
        find.textContaining('Resolved note', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Open note', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.text('lib/a.dart:9'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Resolved note', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('1 comment'), findsNothing);
    });

    testWidgets('an empty conversation is one quiet line', (tester) async {
      await pump(tester, const <MobilePullRequestComment>[]);

      expect(find.text('No comments yet.'), findsOneWidget);
      expect(find.byTooltip('Open Comment'), findsNothing);
    });
  });
}
