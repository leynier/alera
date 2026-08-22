part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexTurnActivityTests() {
  testWidgets(
    'mobile preserves bounded file-change counts in activity summaries',
    (tester) async {
      final client = FakeMobileCodexClient(
        timelineCells: const <Object?>[
          <String, Object?>{
            'id': 'large-file-change',
            'turnId': 'turn-tools',
            'kind': 'diff',
            'status': 'completed',
            'metadata': <String, Object?>{
              'itemType': 'fileChange',
              'changesCount': 40,
              'changes': <Object?>[
                <String, Object?>{
                  'truncated': true,
                  'message': 'Additional list items were omitted.',
                },
              ],
            },
          },
          <String, Object?>{
            'id': 'validation-command',
            'turnId': 'turn-tools',
            'kind': 'command',
            'status': 'completed',
            'title': 'Validate changes',
          },
        ],
      );
      addTearDown(client.dispose);
      await _pumpScreen(tester, client: client, hostId: 'host-large-changes');

      expect(find.text('Edited 40 files, Ran 1 command'), findsOneWidget);
    },
  );

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

  testWidgets('mobile shows dedicated context compaction lifecycle rows', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'command-before-compaction',
          'turnId': 'turn-active',
          'kind': 'command',
          'status': 'completed',
          'title': 'Read one file',
          'metadata': <String, Object?>{'itemType': 'commandExecution'},
        },
        <String, Object?>{
          'id': 'compacting',
          'turnId': 'turn-active',
          'kind': 'toolCall',
          'status': 'inProgress',
          'title': 'Context automatically compacting',
          'isStreaming': true,
          'metadata': <String, Object?>{'itemType': 'contextCompaction'},
        },
        <String, Object?>{
          'id': 'compacted',
          'turnId': 'turn-complete',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'Compacted context',
          'metadata': <String, Object?>{'itemType': 'contextCompaction'},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-compaction');

    expect(find.text('Compacting'), findsOneWidget);
    expect(find.text('Compacted'), findsOneWidget);
    expect(find.text('Context automatically compacting'), findsNothing);
    expect(find.text('Ran Compacting'), findsNothing);
    expect(find.byIcon(AleraIcons.contextCompact), findsNWidgets(2));
  });

  testWidgets('mobile shows command actions without command output', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'command-actions',
          'turnId': 'turn-tools',
          'kind': 'command',
          'status': 'completed',
          'title': 'Read file',
          'metadata': <String, Object?>{
            'commandActions': <Object?>[
              <String, Object?>{'type': 'read', 'path': '/repo/README.md'},
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-command-actions');

    expect(find.text('Command Actions'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);
    expect(find.text('/repo/README.md'), findsOneWidget);
  });

  testWidgets('mobile renders structured MCP tool arguments and responses', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'mcp-calendar',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'calendar.lookup',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'server': 'codex_apps',
            'tool': 'calendar.lookup',
            'arguments': <String, Object?>{'calendarId': 'work'},
            'result': <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': 'Found 2 events'},
              ],
              'structuredContent': <String, Object?>{'count': 2},
            },
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-tool');

    expect(find.text('Used calendar.lookup'), findsOneWidget);
    expect(find.text('Ran 1 command'), findsNothing);
    await tester.tap(find.text('Used calendar.lookup'));
    await tester.pump();

    expect(find.text('Used calendar.lookup'), findsOneWidget);
    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Calendar Id'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Response'), findsOneWidget);
    expect(find.text('Found 2 events'), findsOneWidget);
    expect(find.text('Structured Content'), findsOneWidget);
    expect(find.text('Count'), findsOneWidget);
    expect(find.textContaining('{"content"'), findsNothing);
  });

  testWidgets('mobile does not repeat web search actions as output', (
    tester,
  ) async {
    const action = <String, Object?>{
      'type': 'search',
      'query': 'Flutter structured tool rendering',
    };
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'web-search',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'detailsText':
              '{"type":"search","query":"Flutter structured tool rendering"}',
          'metadata': <String, Object?>{
            'itemType': 'webSearch',
            'query': 'Flutter structured tool rendering',
            'action': action,
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-web-search');

    await tester.tap(
      find.text('Searched the Web for Flutter structured tool rendering'),
    );
    await tester.pump();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
  });

  testWidgets('mobile preserves markdown-only tool output', (tester) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'mcp-markdown',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'notes.read',
          'markdownText': '**Rendered tool output**',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'notes.read',
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-markdown');

    await tester.tap(find.text('Used notes.read'));
    await tester.pump();

    expect(find.text('Output'), findsOneWidget);
    expect(find.text('**Rendered tool output**'), findsOneWidget);
  });

  testWidgets('mobile reveals large structured tool responses incrementally', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = FakeMobileCodexClient(
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'mcp-records',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'records.list',
          'metadata': <String, Object?>{
            'itemType': 'mcpToolCall',
            'tool': 'records.list',
            'result': <String, Object?>{
              'records': List<String>.generate(
                30,
                (index) => 'Record ${index + 1}',
              ),
            },
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-records');

    await tester.tap(find.text('Used records.list'));
    await tester.pump();

    expect(find.text('Record 24'), findsOneWidget);
    expect(find.text('Record 25'), findsNothing);
    await tester.tap(find.text('Show 6 More'));
    await tester.pump();
    expect(find.text('Record 30'), findsOneWidget);
  });

  testWidgets('mobile keeps expanded tool pages across snapshots', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, Object?> toolCell() => <String, Object?>{
      'id': 'mcp-records',
      'turnId': 'turn-tools',
      'kind': 'toolCall',
      'status': 'completed',
      'title': 'records.list',
      'metadata': <String, Object?>{
        'itemType': 'mcpToolCall',
        'tool': 'records.list',
        'result': <String, Object?>{
          'records': List<String>.generate(
            30,
            (index) => 'Record ${index + 1}',
          ),
        },
      },
    };
    final client = FakeMobileCodexClient(
      initialThreadId: 'thread-current',
      initialSnapshot: <String, Object?>{
        'timelineCells': <Object?>[toolCell()],
        'pendingRequests': const <Object?>[],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-pages');

    await tester.tap(find.text('Used records.list'));
    await tester.pump();
    await tester.tap(find.text('Show 6 More'));
    await tester.pump();
    expect(find.text('Record 30'), findsOneWidget);

    client.emit(
      MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-mcp-pages',
        'threadId': 'thread-current',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[toolCell()],
          'pendingRequests': const <Object?>[],
        },
      }),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Record 30'), findsOneWidget);
    expect(find.text('Show 6 More'), findsNothing);
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
