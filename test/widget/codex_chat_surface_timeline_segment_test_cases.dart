part of 'codex_chat_surface_test.dart';

void registerCodexTimelineSegmentTests() {
  testWidgets('keeps MCP startup status above conversation messages', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'before-mcp',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Message before startup status',
        },
        <String, Object?>{
          'id': 'mcp-startup-docs',
          'turnId': 'turn-later',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'Docs MCP server',
          'subtitle': 'ready',
          'metadata': <String, Object?>{
            'itemType': 'mcpServerStartup',
            'status': 'ready',
          },
        },
        <String, Object?>{
          'id': 'after-mcp',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Message after startup status',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final status = tester.getTopLeft(find.text('Docs MCP server')).dy;
    final before = tester
        .getTopLeft(find.text('Message before startup status'))
        .dy;
    final after = tester
        .getTopLeft(find.text('Message after startup status'))
        .dy;
    expect(status, lessThan(before));
    expect(before, lessThan(after));
  });

  testWidgets('keeps Working visible and collapses activity on completion', (
    tester,
  ) async {
    final startedAt = DateTime.now()
        .subtract(const Duration(seconds: 3))
        .toUtc()
        .toIso8601String();
    List<Object?> cells({bool assistantStreaming = false}) => <Object?>[
      <String, Object?>{
        'id': 'request-worked',
        'turnId': 'turn-worked',
        'kind': 'userMessage',
        'status': 'completed',
        'createdAt': startedAt,
        'updatedAt': startedAt,
        'markdownText': 'Inspect the files',
      },
      <String, Object?>{
        'id': 'read-worked',
        'turnId': 'turn-worked',
        'kind': 'command',
        'status': 'completed',
        'createdAt': startedAt,
        'updatedAt': startedAt,
        'title': 'Read file',
        'metadata': <String, Object?>{
          'commandActions': <Object?>[
            <String, Object?>{'type': 'read', 'path': '/repo/one.dart'},
          ],
        },
      },
      <String, Object?>{
        'id': 'search-worked',
        'turnId': 'turn-worked',
        'kind': 'command',
        'status': 'completed',
        'createdAt': startedAt,
        'updatedAt': startedAt,
        'title': 'Search files',
        'metadata': <String, Object?>{
          'commandActions': <Object?>[
            <String, Object?>{'type': 'search', 'query': 'needle'},
          ],
        },
      },
      if (assistantStreaming)
        <String, Object?>{
          'id': 'assistant-worked',
          'turnId': 'turn-worked',
          'kind': 'assistantMessage',
          'status': 'inProgress',
          'isStreaming': true,
          'createdAt': startedAt,
          'updatedAt': startedAt,
          'markdownText': 'The first streamed response',
        },
    ];
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-worked',
      timelineCells: cells(),
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, settle: false);

    expect(
      find.byKey(const ValueKey<String>('codex-working-indicator')),
      findsOneWidget,
    );
    expect(find.textContaining('Working for'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('worked-action-group-read-worked')),
      findsOneWidget,
    );

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': cells(assistantStreaming: true),
          'pendingRequests': const <Object?>[],
          'activeTurnId': 'turn-worked',
        },
      }),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('codex-working-indicator')),
      findsOneWidget,
    );
    expect(find.text('The first streamed response'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('worked-action-group-read-worked')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('codex-working-indicator')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('worked-action-group-read-worked')),
      findsNothing,
    );

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': cells(),
          'pendingRequests': const <Object?>[],
          'activeTurnId': null,
        },
      }),
    );
    await tester.pump();
    await tester.pump(AleraTokens.durationFast);

    expect(
      find.byKey(const ValueKey<String>('worked-divider')),
      findsOneWidget,
    );
    expect(find.textContaining('Worked for'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('worked-action-group-read-worked')),
      findsNothing,
    );
  });

  testWidgets('keeps an expanded tool group open when earlier activity lands', (
    tester,
  ) async {
    const readOne = <String, Object?>{
      'id': 'read-one',
      'turnId': 'turn-tools',
      'kind': 'command',
      'status': 'completed',
      'title': 'Read first file',
      'detailsText': 'First file output',
      'metadata': <String, Object?>{
        'commandActions': <Object?>[
          <String, Object?>{'type': 'read', 'path': '/repo/one.dart'},
        ],
      },
    };
    const readTwo = <String, Object?>{
      'id': 'read-two',
      'turnId': 'turn-tools',
      'kind': 'command',
      'status': 'completed',
      'title': 'Read second file',
      'detailsText': 'Second file output',
      'metadata': <String, Object?>{
        'commandActions': <Object?>[
          <String, Object?>{'type': 'read', 'path': '/repo/two.dart'},
        ],
      },
    };
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-tools',
      timelineCells: const <Object?>[readOne, readTwo],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, settle: false);

    await tester.tap(
      find.byKey(const ValueKey<String>('worked-action-group-read-one')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('worked-action-read-one')),
    );
    await tester.pump();
    expect(find.text('First file output'), findsOneWidget);

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': const <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'progress-before-tools',
              'turnId': 'turn-tools',
              'kind': 'progressText',
              'status': 'completed',
              'markdownText': 'Inspecting the workspace',
            },
            readOne,
            readTwo,
          ],
          'pendingRequests': <Object?>[],
          'activeTurnId': 'turn-tools',
        },
      }),
    );
    await tester.pump();
    await tester.pump(AleraTokens.durationFast);

    expect(find.text('First file output'), findsOneWidget);
  });

  testWidgets('streams plan content inside the plan card', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-plan',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'request',
          'turnId': 'turn-plan',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Create a plan',
        },
        <String, Object?>{
          'id': 'plan',
          'turnId': 'turn-plan',
          'kind': 'plan',
          'status': 'inProgress',
          'isStreaming': true,
          'markdownText': '# First section',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, settle: false);

    expect(find.text('Writing Plan'), findsOneWidget);
    expect(find.text('First section'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('codex-plan-writing-indicator')),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps plan decisions and model configuration in the footer', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'request',
          'turnId': 'turn-plan',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Create a plan',
        },
        <String, Object?>{
          'id': 'plan',
          'turnId': 'turn-plan',
          'kind': 'plan',
          'status': 'completed',
          'markdownText': '# Ready plan',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, planMode: true);

    expect(find.text('Implement this plan?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('codex-plan-question-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('codex-model-configuration')),
      findsOneWidget,
    );
    final cardBottom = tester.getBottomRight(
      find.byKey(const ValueKey<String>('codex-plan-question-card')),
    );
    final modelTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('codex-model-configuration')),
    );
    final modelBottom = tester.getBottomRight(
      find.byKey(const ValueKey<String>('codex-model-configuration')),
    );
    final surfaceBottom = tester.getBottomRight(find.byType(CodexChatSurface));
    expect(cardBottom.dy, lessThan(modelTop.dy));
    expect(surfaceBottom.dy - modelBottom.dy, greaterThanOrEqualTo(0));
    expect(
      surfaceBottom.dy - modelBottom.dy,
      lessThanOrEqualTo(AleraTokens.space24),
    );
  });

  testWidgets('groups tool activity with singular and plural counts', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-tools',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'read-one',
          'turnId': 'turn-tools',
          'kind': 'command',
          'status': 'completed',
          'title': 'Read first file',
          'metadata': <String, Object?>{
            'commandActions': <Object?>[
              <String, Object?>{'type': 'read', 'path': '/repo/one.dart'},
            ],
          },
        },
        <String, Object?>{
          'id': 'read-two',
          'turnId': 'turn-tools',
          'kind': 'command',
          'status': 'completed',
          'title': 'Read second file',
          'metadata': <String, Object?>{
            'commandActions': <Object?>[
              <String, Object?>{'type': 'read', 'path': '/repo/two.dart'},
            ],
          },
        },
        <String, Object?>{
          'id': 'command',
          'turnId': 'turn-tools',
          'kind': 'command',
          'status': 'completed',
          'title': 'dart analyze',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Read 2 files, ran 1 command'), findsOneWidget);
  });

  testWidgets('counts web searches without calling them files', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-web',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'web-one',
          'turnId': 'turn-web',
          'kind': 'toolCall',
          'status': 'completed',
          'metadata': <String, Object?>{
            'itemType': 'webSearch',
            'query': 'first query',
          },
        },
        <String, Object?>{
          'id': 'web-two',
          'turnId': 'turn-web',
          'kind': 'toolCall',
          'status': 'completed',
          'metadata': <String, Object?>{
            'itemType': 'webSearch',
            'query': 'second query',
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Searched the web 2 times'), findsOneWidget);
    expect(find.text('Searched 2 files'), findsNothing);
  });

  testWidgets('uses the dedicated viewed image activity icon', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'view-image',
          'turnId': 'turn-tools',
          'kind': 'toolCall',
          'status': 'completed',
          'title': 'Viewed image',
          'subtitle': '/repo/image.png',
          'metadata': <String, Object?>{
            'itemType': 'imageView',
            'path': '/repo/image.png',
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final row = find.byKey(const ValueKey<String>('worked-action-view-image'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(AleraIcons.viewImage)),
      findsOneWidget,
    );
    expect(find.text('Viewed image · /repo/image.png'), findsOneWidget);
  });
}

Future<void> _pumpTimelineSegmentSurface(
  WidgetTester tester,
  _SurfaceRuntimeClient client, {
  bool settle = true,
  bool planMode = false,
  double height = 800,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(
          () => _TimelineSegmentSettings(planMode: planMode),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: height,
            child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
  if (settle) await tester.pumpAndSettle();
}
