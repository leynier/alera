part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexTurnActivityTests() {
  testWidgets('mobile groups viewed images with adjacent tool activity', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'command',
          'turnId': 'turn-tools',
          'kind': 'command',
          'status': 'completed',
          'title': 'inspect',
          'detailsText': 'Command output remains visible.',
          'metadata': <String, Object?>{'itemType': 'commandExecution'},
        },
        <String, Object?>{
          'id': 'image',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'Viewed image',
          'subtitle': '/repo/logo.png',
          'metadata': <String, Object?>{
            'itemType': 'imageView',
            'path': '/repo/logo.png',
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-tools');

    final summary = find.text('Viewed 1 image, Ran 1 command');
    expect(summary, findsOneWidget);
    expect(find.text('Command output remains visible.'), findsNothing);
    await tester.tap(summary);
    await tester.pump();
    expect(find.text('Viewed image · /repo/logo.png'), findsOneWidget);
    expect(find.text('Command output remains visible.'), findsOneWidget);
    expect(find.byIcon(AleraIcons.viewImage), findsOneWidget);
  });

  testWidgets('mobile Worked separators do not expose a no-op expander', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'worked',
          'turnId': 'turn-worked',
          'kind': 'turnSeparator',
          'status': 'completed',
          'metadata': <String, Object?>{'durationMs': 1000},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-worked');

    final label = find.text('Worked for 1s');
    expect(label, findsOneWidget);
    expect(
      find.ancestor(of: label, matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('mobile Working expands activity and can collapse the turn', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-active',
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'turn-active',
            'turnId': 'turn-active',
            'kind': 'turnSeparator',
            'status': 'info',
            'createdAt': '2026-08-09T12:00:00Z',
          },
          <String, Object?>{
            'id': 'read-one',
            'turnId': 'turn-active',
            'kind': 'command',
            'status': 'completed',
            'title': 'Read one file',
            'detailsText': 'First output',
          },
          <String, Object?>{
            'id': 'read-two',
            'turnId': 'turn-active',
            'kind': 'command',
            'status': 'inProgress',
            'title': 'Read another file',
            'detailsText': 'Second output',
            'isStreaming': true,
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-working-turn');

    final working = find.textContaining('Working for');
    expect(working, findsOneWidget);
    expect(
      tester
          .getSize(
            find.ancestor(of: working, matching: find.byType(InkWell)).first,
          )
          .height,
      greaterThanOrEqualTo(AleraTokens.minTapTarget),
    );
    expect(find.text('Read 2 files'), findsOneWidget);
    expect(find.text('First output'), findsOneWidget);

    await tester.tap(find.text('Read 2 files'));
    await tester.pump();
    expect(find.text('First output'), findsNothing);

    await tester.tap(working);
    await tester.pump();
    expect(find.text('Read 2 files'), findsNothing);
  });

  testWidgets('mobile Worked collapses multi-action turns by default', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'turn-complete',
          'turnId': 'turn-complete',
          'kind': 'turnSeparator',
          'status': 'completed',
          'metadata': <String, Object?>{'computedDurationMs': 2000},
        },
        <String, Object?>{
          'id': 'read-one',
          'turnId': 'turn-complete',
          'kind': 'command',
          'status': 'completed',
          'title': 'Read one file',
        },
        <String, Object?>{
          'id': 'read-two',
          'turnId': 'turn-complete',
          'kind': 'command',
          'status': 'completed',
          'title': 'Read another file',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-worked-turn');

    final worked = find.text('Worked for 2s');
    expect(worked, findsOneWidget);
    expect(
      tester
          .getSize(
            find.ancestor(of: worked, matching: find.byType(InkWell)).first,
          )
          .height,
      greaterThanOrEqualTo(AleraTokens.minTapTarget),
    );
    expect(find.text('Read 2 files'), findsNothing);

    await tester.tap(worked);
    await tester.pump();
    expect(find.text('Read 2 files'), findsOneWidget);
  });
}
