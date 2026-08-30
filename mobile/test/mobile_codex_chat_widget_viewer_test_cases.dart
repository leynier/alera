part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexViewerTests() {
  testWidgets('mobile renders empty text file previews without load controls', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['empty.md'],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'empty-file-link',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[empty.md](empty.md)',
        },
      ],
      workspaceFileReader:
          (workspaceId, relativePath, cwd, offset, length) async {
            return const MobileWorkspaceFileRange(
              relativePath: 'empty.md',
              offset: 0,
              nextOffset: 0,
              totalBytes: 0,
              mimeType: 'text/markdown',
              isText: true,
              bytes: <int>[],
            );
          },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-empty-preview');

    await tester.tap(find.text('empty.md'));
    await tester.pump();
    await tester.runAsync(
      () => Future.pause(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ListView), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '',
      ),
      findsOneWidget,
    );
    expect(find.text('Load More'), findsNothing);
  });

  testWidgets('mobile scrolls to and highlights a linked text line', (
    tester,
  ) async {
    final contents = List<String>.generate(
      200,
      (index) => 'line ${index + 1}',
    ).join('\n');
    final bytes = utf8.encode(contents);
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['long.md'],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'long-file-link',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[long.md](long.md#L150)',
        },
      ],
      workspaceFileReader:
          (workspaceId, relativePath, cwd, offset, length) async {
            return MobileWorkspaceFileRange(
              relativePath: 'long.md',
              offset: 0,
              nextOffset: bytes.length,
              totalBytes: bytes.length,
              mimeType: 'text/markdown',
              isText: true,
              bytes: bytes,
            );
          },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-target-line');

    await tester.tap(find.text('long.md'));
    await tester.pump();
    await tester.runAsync(
      () => Future.pause(const Duration(milliseconds: 100)),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final targetLine = find.text('line 150');
    expect(targetLine, findsOneWidget);
    expect(
      find.ancestor(
        of: targetLine,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.color == AleraTokens.accentSubtle,
        ),
      ),
      findsOneWidget,
    );
  });
}
