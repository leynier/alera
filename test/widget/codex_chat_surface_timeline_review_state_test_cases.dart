part of 'codex_chat_surface_test.dart';

void registerCodexTimelineReviewStateTests() {
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
