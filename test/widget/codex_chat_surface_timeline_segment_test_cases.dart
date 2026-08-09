part of 'codex_chat_surface_test.dart';

void registerCodexTimelineSegmentTests() {
  testWidgets('renders warning notices with the warning tone', (tester) async {
    const warningText =
        'Skill descriptions were shortened to fit the skills context budget.';
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'skills-warning',
          'kind': 'systemNotice',
          'status': 'info',
          'markdownText': warningText,
          'metadata': <String, Object?>{'noticeType': 'warning'},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final warning = tester.widget<Text>(find.text(warningText));
    expect(warning.style?.color, AleraTokens.warning);
    expect(
      find.byKey(const ValueKey<String>('codex-warning-notice-skills-warning')),
      findsOneWidget,
    );
    expect(find.byIcon(AleraIcons.warning), findsOneWidget);
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

  testWidgets('renders generic attachments separately from message text', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'user-file',
          'turnId': 'turn-file',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Inspect this',
          'metadata': <String, Object?>{
            'attachments': <Object?>[
              <String, Object?>{
                'path': '/tmp/data.csv',
                'displayName': 'data.csv',
                'kind': 'file',
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Inspect this'), findsOneWidget);
    expect(find.text('data.csv'), findsOneWidget);
    expect(find.textContaining('Attachments Files:'), findsNothing);
    expect(find.text('/tmp/data.csv'), findsNothing);
  });

  testWidgets('shows assistant actions only after streaming completes', (
    tester,
  ) async {
    Map<String, Object?> assistant({required bool streaming}) =>
        <String, Object?>{
          'id': 'assistant',
          'turnId': 'turn-stream',
          'kind': 'assistantMessage',
          'status': streaming ? 'inProgress' : 'completed',
          'isStreaming': streaming,
          'createdAt': '2026-08-02T12:00:00Z',
          'markdownText': 'Streaming response',
        };
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-stream',
      timelineCells: <Object?>[assistant(streaming: true)],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, settle: false);

    expect(find.byTooltip('Copy Message'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('codex-message-timestamp')),
      findsNothing,
    );

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[assistant(streaming: false)],
          'pendingRequests': const <Object?>[],
          'activeTurnId': null,
        },
      }),
    );
    await tester.pump();
    await tester.pump(AleraTokens.durationFast);

    expect(find.byTooltip('Copy Message'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('codex-message-timestamp')),
      findsOneWidget,
    );
  });

  testWidgets('hides unknown message timestamps', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'legacy-assistant',
          'turnId': 'legacy-turn',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Legacy response',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.byTooltip('Copy Message'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('codex-message-timestamp')),
      findsNothing,
    );
  });

  testWidgets('shows question option descriptions without truncating them', (
    tester,
  ) async {
    const description =
        'Includes behavior, empty states, errors, and compatibility details.';
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 9,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'question': 'Choose a scope',
                'options': <Object?>[
                  <String, Object?>{
                    'label': 'Complete Flow',
                    'description': description,
                  },
                ],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Choose a scope'), findsOneWidget);
    expect(find.text('Complete Flow'), findsOneWidget);
    expect(find.text(description), findsOneWidget);
  });

  testWidgets('masks secret custom question answers', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 10,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'secret',
                'question': 'Enter a secret',
                'isOther': true,
                'isSecret': true,
                'options': <Object?>[
                  <String, Object?>{'label': 'Use Existing'},
                ],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('codex-inline-answer-row')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.obscureText, isTrue);
  });

  testWidgets('submits multi-select choices together with a custom answer', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 11,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'question': 'Choose scopes',
                'isOther': true,
                'isMultiSelect': true,
                'options': <Object?>[
                  <String, Object?>{'label': 'Core'},
                ],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Core'));
    await tester.pump();
    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    final field = find.descendant(
      of: find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'Documentation');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump();

    final result = client.responsePayloads.single['result']! as Map;
    final answers = result['answers']! as Map;
    final scope = answers['scope']! as Map;
    expect(scope['answers'], <String>['Core', 'Documentation']);
  });

  testWidgets('dismisses a maximized plan removed by a new snapshot', (
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
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.byTooltip('Maximize Plan'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('codex-plan-card-maximized')),
      findsOneWidget,
    );

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': const <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[],
          'activeTurnId': null,
        },
      }),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('codex-plan-card-maximized')),
      findsNothing,
    );
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

final class _TimelineSegmentSettings extends SettingsController {
  _TimelineSegmentSettings({required this.planMode});

  final bool planMode;

  @override
  AleraSettings build() => AleraSettings.defaults.copyWith(
    codexChat: CodexChatSettings(planMode: planMode),
  );
}
