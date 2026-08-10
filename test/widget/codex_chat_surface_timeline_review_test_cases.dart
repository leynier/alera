part of 'codex_chat_surface_test.dart';

void registerCodexTimelineReviewTests() {
  testWidgets('keeps reasoning transient and shows Working instead', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      activeTurnId: 'turn-reasoning',
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'request',
          'turnId': 'turn-reasoning',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Inspect this',
        },
        <String, Object?>{
          'id': 'turn-reasoning-cell',
          'turnId': 'turn-reasoning',
          'kind': 'reasoning',
          'status': 'completed',
          'title': 'Turn Reasoning',
          'markdownText': 'Turn reasoning details',
        },
        <String, Object?>{
          'id': 'standalone-reasoning-cell',
          'kind': 'reasoning',
          'status': 'completed',
          'title': 'Standalone Reasoning',
          'markdownText': 'Standalone reasoning details',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Turn Reasoning'), findsNothing);
    expect(find.text('Standalone Reasoning'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('codex-working-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('focusing a free-text question snoozes auto-resolution', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 12,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'autoResolutionMs': 5000,
            'questions': <Object?>[
              <String, Object?>{
                'id': 'details',
                'question': 'Add details',
                'options': <Object?>[],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(
      find.byKey(const ValueKey<String>('question-answer-details')),
    );
    await tester.pump();

    expect(
      client.requestTypes.where((type) => type == 'codex.request.snooze'),
      hasLength(1),
    );
  });

  testWidgets('normal plan questions do not show model configuration', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 121,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'priority',
                'question': 'Which part of the plan should we implement first?',
                'options': <Object?>[
                  <String, Object?>{'label': 'Reliability'},
                  <String, Object?>{'label': 'Performance'},
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

    expect(
      find.byKey(const ValueKey<String>('codex-question-model-selector')),
      findsNothing,
    );
  });

  testWidgets('shows one editor for an Other-only question', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 13,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'details',
                'question': 'Add details',
                'isOther': true,
                'options': <Object?>[],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('codex-inline-answer-row')),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('question-answer-details')),
      findsNothing,
    );
  });

  testWidgets('keeps concurrent question requests reachable', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 14,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'first',
                'question': 'First request',
                'options': <Object?>[],
              },
            ],
          },
        },
        <String, Object?>{
          'id': 15,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'second',
                'question': 'Second request',
                'options': <Object?>[],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Request 1 of 2'), findsOneWidget);
    expect(find.text('First request'), findsOneWidget);
    await tester.tap(find.byTooltip('Next Pending Question'));
    await tester.pump();

    expect(find.text('Request 2 of 2'), findsOneWidget);
    expect(find.text('Second request'), findsOneWidget);
  });

  testWidgets('shows the complete question prompt', (tester) async {
    const prompt =
        'Explain the complete deployment strategy, including rollback, '
        'monitoring, ownership, validation, and recovery requirements.';
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 16,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'strategy',
                'question': prompt,
                'options': <Object?>[],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final promptText = tester.widget<Text>(find.text(prompt));
    expect(promptText.maxLines, isNull);
    expect(promptText.overflow, isNull);
  });

  testWidgets('keeps question controls bounded in a short tab', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 17,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'question': 'Choose a scope',
                'options': <Object?>[
                  <String, Object?>{'label': 'One'},
                  <String, Object?>{'label': 'Two'},
                  <String, Object?>{'label': 'Three'},
                  <String, Object?>{'label': 'Four'},
                  <String, Object?>{'label': 'Five'},
                  <String, Object?>{'label': 'Six'},
                ],
              },
            ],
          },
        },
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, height: 220);

    expect(tester.takeException(), isNull);
    expect(find.text('Choose a scope'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
  });

  testWidgets('docks blocking questions at the bottom of the chat', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 18,
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
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final surfaceBottom = tester.getBottomRight(find.byType(CodexChatSurface));
    final cardBottom = tester.getBottomRight(
      find.byKey(const ValueKey<String>('codex-question-card')),
    );
    expect(surfaceBottom.dy - cardBottom.dy, AleraTokens.space12);
  });

  registerCodexTimelineReviewStateTests();
}
