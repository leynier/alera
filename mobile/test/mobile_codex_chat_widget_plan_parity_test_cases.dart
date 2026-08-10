part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexPlanParityTests() {
  testWidgets('mobile keeps Working visible while an answer streams', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-working',
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'user',
            'kind': 'userMessage',
            'status': 'completed',
            'turnId': 'turn-working',
            'markdownText': 'Start',
          },
          <String, Object?>{
            'id': 'assistant',
            'kind': 'assistantMessage',
            'status': 'inProgress',
            'turnId': 'turn-working',
            'markdownText': 'Streaming answer',
            'isStreaming': true,
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-working-stream');

    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Streaming answer'), findsOneWidget);
  });

  testWidgets('mobile shows model controls for implement-plan questions', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 'plan-question',
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'question',
                  'question': 'Implement this plan?',
                  'options': <Object?>[
                    <String, Object?>{'label': 'Yes'},
                  ],
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-plan-question');

    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-model-selector')),
      findsOneWidget,
    );
  });

  testWidgets('mobile hides model controls for normal questions', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 'normal-question',
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{
                  'id': 'question',
                  'question': 'Choose a scope',
                  'options': <Object?>[
                    <String, Object?>{'label': 'Workspace'},
                  ],
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-normal-question');

    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-model-selector')),
      findsNothing,
    );
  });

  testWidgets('mobile keeps a streamed plan fade stable until completion', (
    tester,
  ) async {
    final longPlan = List<String>.filled(40, 'A long plan line.').join('\n\n');
    final client = FakeMobileCodexClient(
      initialSnapshot: <String, Object?>{
        'activeTurnId': 'turn-plan',
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'plan',
            'turnId': 'turn-plan',
            'kind': 'plan',
            'status': 'inProgress',
            'markdownText': longPlan,
            'isStreaming': true,
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-plan-fade');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-preview-fade')),
      findsOneWidget,
    );

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-plan-fade',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'plan',
              'turnId': 'turn-plan',
              'kind': 'plan',
              'status': 'inProgress',
              'markdownText': 'Short streamed plan.',
              'isStreaming': true,
            },
          ],
          'timelineRemovedIds': <Object?>[],
          'eventsAppend': <Object?>[],
          'activeTurnId': 'turn-plan',
        },
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-preview-fade')),
      findsOneWidget,
    );

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-plan-fade',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'plan',
              'turnId': 'turn-plan',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': 'Short completed plan.',
              'isStreaming': false,
            },
          ],
          'timelineRemovedIds': <Object?>[],
          'eventsAppend': <Object?>[],
          'activeTurnId': null,
        },
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-preview-fade')),
      findsNothing,
    );
  });

  testWidgets('mobile preserves plan overflow across sliver eviction', (
    tester,
  ) async {
    final longPlan = List<String>.filled(40, 'A long plan line.').join('\n\n');
    final client = FakeMobileCodexClient(
      initialSnapshot: <String, Object?>{
        'activeTurnId': 'turn-plan-eviction',
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'plan-eviction',
            'turnId': 'turn-plan-eviction',
            'kind': 'plan',
            'status': 'inProgress',
            'markdownText': longPlan,
            'isStreaming': true,
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-plan-eviction');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-preview-fade')),
      findsOneWidget,
    );

    client.emit(
      MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-plan-eviction',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            for (var index = 0; index < 40; index += 1)
              <String, Object?>{
                'id': 'answer-$index',
                'turnId': 'turn-plan-eviction',
                'kind': 'assistantMessage',
                'status': 'completed',
                'markdownText': List<String>.filled(
                  4,
                  'Answer row $index keeps the plan outside the viewport.',
                ).join('\n\n'),
              },
          ],
          'timelineRemovedIds': <Object?>[],
          'eventsAppend': <Object?>[],
          'activeTurnId': 'turn-plan-eviction',
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-preview')),
      findsNothing,
    );

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-plan-eviction',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'plan-eviction',
              'turnId': 'turn-plan-eviction',
              'kind': 'plan',
              'status': 'inProgress',
              'markdownText': 'Short streamed plan.',
              'isStreaming': true,
            },
          ],
          'timelineRemovedIds': <Object?>[],
          'eventsAppend': <Object?>[],
          'activeTurnId': 'turn-plan-eviction',
        },
      }),
    );
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 12000));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('mobile-codex-plan-preview-fade')),
      findsOneWidget,
    );
  });
}
