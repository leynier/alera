part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexTimelineTests() {
  testWidgets('mobile restores a Codex draft after switching tabs', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-draft',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);

    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-draft',
      tabId: 'codex-a',
      container: container,
    );
    final composer = find.byType(TextField).last;
    await tester.enterText(composer, 'Keep this mobile draft');
    final drafts = container.read(mobileCodexComposerDraftStoreProvider);
    drafts.write(
      'host-draft',
      'codex-a',
      drafts
          .read('host-draft', 'codex-a')
          .copyWith(
            attachments: const <Map<String, Object?>>[
              <String, Object?>{
                'type': 'file',
                'origin': 'attachment',
                'name': 'notes.md',
                'path': '/tmp/notes.md',
              },
            ],
          ),
    );

    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-draft',
      tabId: 'codex-b',
      container: container,
    );
    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);

    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-draft',
      tabId: 'codex-a',
      container: container,
    );
    expect(
      tester.widget<TextField>(composer).controller!.text,
      'Keep this mobile draft',
    );
    expect(find.text('notes.md'), findsOneWidget);
  });

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

    final label = find.text('Worked For 1s');
    expect(label, findsOneWidget);
    expect(
      find.ancestor(of: label, matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('mobile screen renders rich timeline and approval actions', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-1');
    expect(find.text('Answer from Codex'), findsOneWidget);
    expect(find.text('Choose a mode'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('Careful'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsWidgets);
    expect(find.textContaining('Current Codex'), findsOneWidget);
    expect(find.textContaining('Ask Codex anything'), findsOneWidget);
  });

  testWidgets('mobile skips questions with an empty answers result', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 21,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{'id': 'first', 'question': 'First question'},
                <String, Object?>{
                  'id': 'second',
                  'question': 'Second question',
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-question-skip');

    await tester.tap(find.byTooltip('Skip Questions'));
    await tester.pump();

    final response = client.calls.lastWhere(
      (call) => call.type == 'codex.response',
    );
    expect(response.payload['result'], <String, Object?>{
      'answers': <String, Object?>{
        'first': <String, Object?>{'answers': <String>[]},
        'second': <String, Object?>{'answers': <String>[]},
      },
    });
  });

  testWidgets('mobile only offers custom answers when the question allows it', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 25,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'fixed',
                  'question': 'Choose one',
                  'isOther': false,
                  'options': <Object?>[
                    <String, Object?>{'label': 'Only choice'},
                  ],
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-fixed-question');

    expect(find.text('Only choice'), findsOneWidget);
    expect(
      find.text('No, and tell Codex what to do differently'),
      findsNothing,
    );
  });

  testWidgets('mobile prevents duplicate pending question responses', (
    tester,
  ) async {
    final response = Completer<Map<String, Object?>>();
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 26,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'isBlocking': false,
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'fixed',
                  'question': 'Choose once',
                  'options': <Object?>[
                    <String, Object?>{'label': 'One'},
                  ],
                },
              ],
            },
          },
        ],
      },
      requestHandler: (type, _) =>
          type == 'codex.response' ? response.future : null,
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-question-once');

    await tester.tap(find.text('One'));
    await tester.tap(find.text('One'));
    expect(
      client.calls.where((call) => call.type == 'codex.request.snooze'),
      hasLength(1),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.response'),
      hasLength(1),
    );

    response.complete(<String, Object?>{});
    await tester.pump();
  });

  testWidgets('mobile obscures secret question answers', (tester) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 22,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'secret',
                  'question': 'Enter a secret',
                  'isSecret': true,
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-secret-question');

    await tester.tap(find.text('Enter your answer'));
    await tester.pump();

    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .any((field) => field.obscureText),
      isTrue,
    );
  });

  testWidgets('mobile keeps custom answer editors isolated by question', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 24,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'secret',
                  'question': 'Secret question',
                  'isSecret': true,
                },
                <String, Object?>{'id': 'plain', 'question': 'Plain question'},
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-question-editors');

    await tester.tap(find.text('Enter your answer'));
    await tester.pump();
    final secretEditor = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.obscureText,
    );
    await tester.enterText(secretEditor, 'private value');
    await tester.tap(find.byTooltip('Next Question'));
    await tester.pump();

    expect(find.text('Plain question'), findsWidgets);
    expect(find.text('private value'), findsNothing);
    await tester.tap(find.text('Enter your answer'));
    await tester.pump();
    final plainEditor = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Enter your answer',
    );
    expect(tester.widget<TextField>(plainEditor).obscureText, isFalse);

    await tester.tap(find.byTooltip('Previous Question'));
    await tester.pump();
    expect(find.text('private value'), findsOneWidget);
    expect(tester.widget<TextField>(secretEditor).obscureText, isTrue);
  });

  testWidgets('mobile preserves MCP elicitation field types', (tester) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 23,
            'method': 'mcpServer/elicitation/request',
            'params': <String, Object?>{
              'mode': 'form',
              'message': 'Choose the MCP execution settings.',
              'requestedSchema': <String, Object?>{
                'type': 'object',
                'required': <String>['count', 'enabled'],
                'properties': <String, Object?>{
                  'count': <String, Object?>{
                    'type': 'integer',
                    'title': 'Count',
                  },
                  'ratio': <String, Object?>{
                    'type': 'number',
                    'title': 'Ratio',
                  },
                  'enabled': <String, Object?>{
                    'type': 'boolean',
                    'title': 'Enabled',
                  },
                  'note': <String, Object?>{'type': 'string', 'title': 'Note'},
                },
              },
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-types');

    expect(find.text('Choose the MCP execution settings.'), findsOneWidget);
    final count = find.widgetWithText(TextField, 'Count');
    final ratio = find.widgetWithText(TextField, 'Ratio');
    expect(
      tester.widget<TextField>(count).keyboardType,
      const TextInputType.numberWithOptions(signed: true),
    );
    expect(
      tester.widget<TextField>(ratio).keyboardType,
      const TextInputType.numberWithOptions(signed: true, decimal: true),
    );
    await tester.enterText(count, ' -7 ');
    await tester.enterText(ratio, ' -1.5 ');
    await tester.enterText(find.widgetWithText(TextField, 'Enabled'), ' true ');
    await tester.pump();
    final accept = find.text('Accept');
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pump();

    final response = client.calls.lastWhere(
      (call) => call.type == 'codex.response',
    );
    expect(response.payload['result'], <String, Object?>{
      'action': 'accept',
      'content': <String, Object?>{'count': -7, 'ratio': -1.5, 'enabled': true},
    });
  });

  testWidgets('mobile can decline MCP elicitation requests', (tester) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 24,
            'method': 'mcpServer/elicitation/request',
            'params': <String, Object?>{
              'mode': 'form',
              'message': 'Share optional MCP settings?',
              'requestedSchema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{},
              },
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-decline');

    expect(find.text('Share optional MCP settings?'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pump();

    final response = client.calls.lastWhere(
      (call) => call.type == 'codex.response',
    );
    expect(response.payload['result'], <String, Object?>{'action': 'decline'});
  });
}
