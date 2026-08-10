part of 'codex_chat_surface_test.dart';

void registerCodexTimelineQuestionAnswerTests() {
  testWidgets('preserves question count and Markdown in partial answers', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'question-answer',
          'kind': 'questionAnswer',
          'status': 'completed',
          'metadata': <String, Object?>{
            'questionCount': 2,
            'questions': <Object?>[
              <String, Object?>{
                'question': 'Choose a scope',
                'answer': 'Use [**API docs**](https://example.com)',
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Asked 2 questions'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('codex-question-answer-header')),
    );
    await tester.pump();

    final markdown = tester.widget<GptMarkdown>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('codex-question-answer-details')),
        matching: find.byType(GptMarkdown),
      ),
    );
    expect(markdown.data, 'Use [**API docs**](https://example.com)');
    final formattedLink = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.textSpan?.toPlainText() ?? '').contains('API docs'),
      ),
    );
    expect(_containsBoldSpan(formattedLink.textSpan), isTrue);
  });
}

bool _containsBoldSpan(InlineSpan? span) {
  if (span is! TextSpan) return false;
  if (span.style?.fontWeight == FontWeight.bold) return true;
  return span.children?.any(_containsBoldSpan) ?? false;
}
