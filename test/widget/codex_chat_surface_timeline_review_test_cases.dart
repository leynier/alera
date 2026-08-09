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

  testWidgets('resets local refinement when the actionable plan changes', (
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
          'id': 'plan-one',
          'turnId': 'turn-plan',
          'kind': 'plan',
          'status': 'completed',
          'markdownText': '# First plan',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, planMode: true);

    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    final refinement = find.descendant(
      of: find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      matching: find.byType(TextField),
    );
    await tester.enterText(refinement, 'Change the first plan');
    await tester.pump();

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshotDelta': <String, Object?>{
          'timelineRemovedIds': <Object?>['plan-one'],
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'plan-two',
              'turnId': 'turn-plan',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': '# Second plan',
            },
          ],
        },
      }),
    );
    await tester.pump();
    await tester.pump(AleraTokens.durationFast);

    expect(find.text('Change the first plan'), findsNothing);
    expect(
      find.text('No, and tell Codex what to do differently'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      findsNothing,
    );
  });

  testWidgets('resets plan refinement state when the active tab changes', (
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
    final activeTab = ValueNotifier<String>('codex-plan-one');
    addTearDown(client.dispose);
    addTearDown(activeTab.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(
            () => _TimelineSegmentSettings(planMode: true),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: ValueListenableBuilder<String>(
                valueListenable: activeTab,
                builder: (context, tabId, _) => CodexChatSurface(
                  workspace: _workspace(),
                  tab: _tab(id: tabId),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    final refinement = find.descendant(
      of: find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      matching: find.byType(TextField),
    );
    await tester.enterText(refinement, 'Keep the first tab draft');
    await tester.pump();
    expect(find.text('Keep the first tab draft'), findsOneWidget);

    activeTab.value = 'codex-plan-two';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(
      find.text('No, and tell Codex what to do differently'),
      findsOneWidget,
    );
    expect(find.text('Keep the first tab draft'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      findsNothing,
    );
  });

  testWidgets('replaces question state when a request id is reused', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 14,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'first',
                'question': 'First prompt',
                'options': <Object?>[
                  <String, Object?>{'label': 'First answer'},
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
    expect(find.text('First prompt'), findsOneWidget);

    client.emit(
      const RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[
            <String, Object?>{
              'id': 14,
              'method': 'item/tool/requestUserInput',
              'params': <String, Object?>{
                'questions': <Object?>[
                  <String, Object?>{
                    'id': 'replacement',
                    'question': 'Replacement prompt',
                    'options': <Object?>[
                      <String, Object?>{'label': 'Replacement answer'},
                    ],
                  },
                ],
              },
            },
          ],
        },
      }),
    );
    await tester.pump();
    await tester.pump(AleraTokens.durationFast);

    expect(find.text('First prompt'), findsNothing);
    expect(find.text('Replacement prompt'), findsOneWidget);
    expect(find.text('Replacement answer'), findsOneWidget);
  });

  testWidgets('allows unanswered pages in a multi-question response', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 15,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'optional-first',
                'question': 'Optional first question',
                'options': <Object?>[
                  <String, Object?>{'label': 'First answer'},
                ],
              },
              <String, Object?>{
                'id': 'second',
                'question': 'Second question',
                'options': <Object?>[
                  <String, Object?>{'label': 'Second answer'},
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

    await tester.tap(find.byTooltip('Next Question'));
    await tester.pump();
    await tester.tap(find.text('Second answer'));
    await tester.pump();

    final result = client.responsePayloads.single['result']! as Map;
    final answers = result['answers']! as Map;
    expect((answers['optional-first']! as Map)['answers'], isEmpty);
    expect((answers['second']! as Map)['answers'], <String>['Second answer']);
  });
}
