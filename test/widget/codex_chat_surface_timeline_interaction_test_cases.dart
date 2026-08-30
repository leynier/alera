part of 'codex_chat_surface_test.dart';

void registerCodexTimelineInteractionTests() {
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
    final timestamp = tester.getRect(
      find.byKey(const ValueKey<String>('codex-message-timestamp')),
    );
    final copyButton = tester.getRect(find.byTooltip('Copy Message'));
    expect(timestamp.center.dy, closeTo(copyButton.center.dy, 0.1));
    final markdownButton = tester.getRect(find.byTooltip('Show Raw Markdown'));
    expect(
      timestamp.left - markdownButton.right,
      closeTo(AleraTokens.space8, 0.1),
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
    expect(find.text('Worked'), findsOneWidget);
    expect(find.textContaining('Worked for'), findsNothing);
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

  testWidgets('keeps timeline content visible above a blocking question', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 19,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'question': 'Choose a scope',
                'options': <Object?>[
                  <String, Object?>{'label': 'Complete'},
                ],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'visible-message',
          'turnId': 'visible-turn',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Timeline remains visible',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final messageBottom = tester.getBottomRight(
      find.text('Timeline remains visible'),
    );
    final cardTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('codex-question-card')),
    );
    expect(messageBottom.dy, lessThan(cardTop.dy));
  });

  testWidgets('centers plan refinement text and fills the single-line action', (
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

    final planBottom = tester.getBottomRight(
      find.text('Ready plan', findRichText: true),
    );
    final planQuestionTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('codex-plan-question-card')),
    );
    expect(planBottom.dy, lessThan(planQuestionTop.dy));

    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    final row = find.byKey(const ValueKey<String>('codex-inline-answer-row'));
    final rowRect = tester.getRect(row);
    final skipRect = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Skip'),
    );
    final hintRect = tester.getRect(
      find.text('Tell Codex what to do differently'),
    );
    expect(skipRect.height, closeTo(AleraTokens.space32, 0.1));
    expect(skipRect.center.dy, closeTo(rowRect.center.dy, 0.1));
    expect(hintRect.center.dy, closeTo(rowRect.center.dy, AleraTokens.space2));

    final input = find.descendant(of: row, matching: find.byType(TextField));
    await tester.enterText(input, 'Use a smaller scope');
    await tester.pump();
    final submitRect = tester.getRect(
      find.widgetWithText(FilledButton, 'Submit'),
    );
    expect(submitRect.height, closeTo(AleraTokens.space32, 0.1));
    expect(submitRect.center.dy, closeTo(rowRect.center.dy, 0.1));
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

final class _TimelineSegmentSettings({required final bool planMode})
    extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults.copyWith(
    codexChat: CodexChatSettings(planMode: planMode),
  );
}
