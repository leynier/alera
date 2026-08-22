part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegression6Tests() {
  testWidgets('mobile keeps Stop available during MCP startup with a draft', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-draft-stop');

    await tester.enterText(find.byType(TextField).last, 'Keep this draft');
    await tester.pump();
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-mcp-draft-stop',
        'snapshot': <String, Object?>{
          'activeTurnId': 'turn-mcp-draft',
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'mcp-startup-draft',
              'kind': 'toolCall',
              'status': 'inProgress',
              'isStreaming': true,
              'metadata': <String, Object?>{'itemType': 'mcpServerStartup'},
            },
          ],
        },
      }),
    );
    await tester.pump();

    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Steer'), findsNothing);
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(
      client.calls.where((call) => call.type == 'codex.turn.interrupt'),
      hasLength(1),
    );
  });

  testWidgets('mobile drops a same-name catalog selection with its token', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.skills.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'shared', 'path': '/skills/shared'},
          ],
        },
        'codex.apps.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'name': 'shared', 'connectorId': 'app-shared'},
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-shared-delete');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, r'$sha');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'shared').first);
    await tester.pump();
    await tester.enterText(composer, r'$shared $sha');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'shared').last);
    await tester.pump();
    await tester.enterText(composer, r'$shared');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(turn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{
        'type': 'skill',
        'name': 'shared',
        'path': '/skills/shared',
      },
      <String, Object?>{'type': 'text', 'text': r'$shared'},
    ]);
  });

  testWidgets('mobile plan actions preserve source Markdown', (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map<Object?, Object?>)['text']
              ?.toString();
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'raw-plan',
          'kind': 'plan',
          'status': 'completed',
          'markdownText': '# Source\n\n- unchanged',
          'renderedMarkdownText': '# Source\n- normalized',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-raw-plan');

    await tester.tap(find.byTooltip('Copy Plan'));
    await tester.pump();

    expect(copiedText, '# Source\n\n- unchanged');
  });

  testWidgets('mobile restores an abandoned submission after remounting', (
    tester,
  ) async {
    final promptLookup = Completer<List<MobileCodexSavedPrompt>>();
    var blockPromptLookup = false;
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[],
      },
      workspaceFiles: const <String>['workspace-capability-marker'],
      savedPromptsLoader: (_, _) => blockPromptLookup
          ? promptLookup.future
          : Future<List<MobileCodexSavedPrompt>>.value(const []),
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-remounted-draft',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-remounted-draft',
      container: container,
    );
    await tester.pumpAndSettle();

    final composer = find.byType(TextField).last;
    blockPromptLookup = true;
    await tester.enterText(composer, '/delayed argument');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);
    expect(
      container
          .read(mobileCodexComposerDraftStoreProvider)
          .read('host-remounted-draft', 'tab-host-remounted-draft')
          .value
          .text,
      isEmpty,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-remounted-draft',
      container: container,
    );
    expect(tester.widget<TextField>(composer).controller?.text, isEmpty);

    promptLookup.complete(const <MobileCodexSavedPrompt>[]);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(composer).controller?.text,
      '/delayed argument',
    );
  });

  testWidgets('mobile recomputes reordered mention byte ranges', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[],
      },
      workspaceFiles: const <String>['docs/first.md', 'docs/second.md'],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mention-ranges');
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-mention-ranges',
        'cwd': '/repo',
      }),
    );
    await tester.pump();

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@first');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('docs/first.md'));
    await tester.pump();
    await tester.enterText(composer, '@second');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('docs/second.md'));
    await tester.pump();
    await tester.enterText(composer, 'docs/second.md docs/first.md');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    final textPart = (turn.payload['input']! as List).cast<Map>().singleWhere(
      (part) => part['type'] == 'text',
    );
    final text = textPart['text']!.toString();
    final bytes = utf8.encode(text);
    final resolved = <String, String>{};
    for (final element in (textPart['text_elements']! as List).cast<Map>()) {
      final range = element['byteRange']! as Map;
      resolved[element['placeholder']!.toString()] = utf8.decode(
        bytes.sublist(range['start']! as int, range['end']! as int),
      );
    }
    expect(resolved, <String, String>{
      'first.md': '/repo/docs/first.md',
      'second.md': '/repo/docs/second.md',
    });
  });

  testWidgets('mobile preserves free-text answers when paging questions', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 101,
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
    await _pumpScreen(tester, client: client, hostId: 'host-free-text-pages');

    await tester.tap(find.text('Enter your answer'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Enter your answer'),
      'First answer',
    );
    await tester.tap(find.byTooltip('Next Question'));
    await tester.pump();
    await tester.tap(find.text('Enter your answer'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Enter your answer'),
      'Second answer',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Submit'));
    await tester.pump();

    final response = client.calls.lastWhere(
      (call) => call.type == 'codex.response',
    );
    expect(response.payload['result'], <String, Object?>{
      'answers': <String, Object?>{
        'first': <String, Object?>{
          'answers': <String>['First answer'],
        },
        'second': <String, Object?>{
          'answers': <String>['Second answer'],
        },
      },
    });
  });

  testWidgets('mobile submits the latest predefined question choice', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 102,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'priority',
                  'question': 'Choose a priority',
                  'isOther': true,
                  'options': <Object?>[
                    <String, Object?>{'label': 'Reliability'},
                  ],
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-latest-choice');

    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'No, and tell Codex what to do differently',
      ),
      'Earlier custom answer',
    );
    await tester.tap(find.text('Reliability'));
    await tester.pumpAndSettle();

    final response = client.calls.lastWhere(
      (call) => call.type == 'codex.response',
    );
    expect(response.payload['result'], <String, Object?>{
      'answers': <String, Object?>{
        'priority': <String, Object?>{
          'answers': <String>['Reliability'],
        },
      },
    });
  });

  testWidgets('mobile combines predefined and custom multi-select answers', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 103,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'checks',
                  'question': 'Choose checks',
                  'isMultiSelect': true,
                  'isOther': true,
                  'options': <Object?>[
                    <String, Object?>{'label': 'Unit tests'},
                  ],
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-multi-custom');

    await tester.tap(find.text('Unit tests'));
    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'No, and tell Codex what to do differently',
      ),
      'Manual QA',
    );
    await tester.tap(find.text('Submit').last);
    await tester.pumpAndSettle();

    final response = client.calls.lastWhere(
      (call) => call.type == 'codex.response',
    );
    expect(response.payload['result'], <String, Object?>{
      'answers': <String, Object?>{
        'checks': <String, Object?>{
          'answers': <String>['Unit tests', 'Manual QA'],
        },
      },
    });
  });

  testWidgets('mobile does not open directory attachments as files', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'user-with-directory',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Review this directory.',
          'metadata': <String, Object?>{
            'attachments': <Object?>[
              <String, Object?>{
                'path': '/workspace/lib',
                'displayName': 'lib',
                'isDirectory': true,
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);

    await _pumpScreen(tester, client: client, hostId: 'host-directory');

    final chip = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, 'lib'),
    );
    expect(chip.onPressed, isNull);
  });

  testWidgets('mobile review requires the selected target value', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-review-target');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '/review');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Uncommitted Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Base Branch').last);
    await tester.pumpAndSettle();

    var startReview = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start Review'),
    );
    expect(startReview.onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'main');
    await tester.pump();

    startReview = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start Review'),
    );
    expect(startReview.onPressed, isNotNull);
  });
}
