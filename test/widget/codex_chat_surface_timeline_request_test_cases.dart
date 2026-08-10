part of 'codex_chat_surface_test.dart';

void registerCodexTimelineRequestTests() {
  testWidgets('distinguishes numeric and string question request ids', (
    tester,
  ) async {
    Map<String, Object?> request(Object id) => <String, Object?>{
      'id': id,
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
    };

    final client = _SurfaceRuntimeClient(
      pendingRequests: <Object?>[request(1)],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    final refinement = find.descendant(
      of: find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      matching: find.byType(TextField),
    );
    await tester.enterText(refinement, 'Numeric request draft');
    await tester.pump();

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': const <Object?>[],
          'pendingRequests': <Object?>[request('1')],
        },
      }),
    );
    await tester.pump();
    await tester.pump(AleraTokens.durationFast);

    expect(find.text('Numeric request draft'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      findsNothing,
    );
  });

  testWidgets('preserves question drafts while navigating pending requests', (
    tester,
  ) async {
    Map<String, Object?> request(String id, String question) =>
        <String, Object?>{
          'id': id,
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'details',
                'question': question,
                'isOther': true,
                'options': <Object?>[],
              },
            ],
          },
        };

    final client = _SurfaceRuntimeClient(
      pendingRequests: <Object?>[
        request('first', 'First request'),
        request('second', 'Second request'),
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('No, and tell Codex what to do differently'));
    await tester.pump();
    final firstAnswer = find.descendant(
      of: find.byKey(const ValueKey<String>('codex-inline-answer-row')),
      matching: find.byType(TextField),
    );
    await tester.enterText(firstAnswer, 'Keep this partial answer');
    await tester.tap(find.byTooltip('Next Pending Question'));
    await tester.pump();
    expect(find.text('Second request'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous Pending Question'));
    await tester.pump();

    expect(find.text('First request'), findsOneWidget);
    expect(find.text('Keep this partial answer'), findsOneWidget);
  });

  testWidgets('hoists warnings above conversation messages', (tester) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'before',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Before warning',
        },
        <String, Object?>{
          'id': 'later-warning',
          'kind': 'systemNotice',
          'status': 'info',
          'markdownText': 'Later warning',
          'metadata': <String, Object?>{'noticeType': 'warning'},
        },
        <String, Object?>{
          'id': 'after',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'After warning',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final before = tester.getTopLeft(find.text('Before warning')).dy;
    final warning = tester.getTopLeft(find.text('Later warning')).dy;
    final after = tester.getTopLeft(find.text('After warning')).dy;
    expect(warning, lessThan(before));
    expect(before, lessThan(after));
  });

  testWidgets('keeps live warnings above history loaded later', (tester) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      historyNextCursor: 'older',
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'live-warning',
          'kind': 'systemNotice',
          'status': 'info',
          'markdownText': 'Live warning',
          'metadata': <String, Object?>{'noticeType': 'warning'},
        },
        <String, Object?>{
          'id': 'live-message',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Live message',
        },
      ],
      historyTimelineCells: const <Object?>[
        <String, Object?>{
          'id': 'history-message',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'History message',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pumpAndSettle();

    final warning = tester.getTopLeft(find.text('Live warning')).dy;
    final history = tester.getTopLeft(find.text('History message')).dy;
    final live = tester.getTopLeft(find.text('Live message')).dy;
    expect(warning, lessThan(history));
    expect(history, lessThan(live));
  });

  testWidgets('keeps the composer available for optional questions', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[
        <String, Object?>{
          'id': 'optional',
          'method': 'item/tool/requestUserInput',
          'params': <String, Object?>{
            'autoResolutionMs': 5000,
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'question': 'Choose an optional scope',
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

    expect(find.text('Choose an optional scope'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('codex-composer')),
      findsOneWidget,
    );
    final questionBottom = tester.getBottomRight(
      find.byKey(const ValueKey<String>('codex-question-card')),
    );
    final composerTop = tester.getTopLeft(
      find.byKey(const ValueKey<String>('codex-composer')),
    );
    expect(questionBottom.dy, lessThan(composerTop.dy));
  });

  testWidgets('keeps a streamed plan fade stable until completion', (
    tester,
  ) async {
    Map<String, Object?> plan(String markdown, {required String status}) =>
        <String, Object?>{
          'id': 'plan-preview',
          'kind': 'plan',
          'status': status,
          'isStreaming': status == 'inProgress',
          'markdownText': markdown,
        };

    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[plan('# Short plan', status: 'inProgress')],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(
      find.byKey(const ValueKey<String>('codex-plan-preview-fade')),
      findsNothing,
    );

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            plan(
              List<String>.filled(40, 'Long plan line').join('\n\n'),
              status: 'inProgress',
            ),
          ],
          'pendingRequests': const <Object?>[],
        },
      }),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('codex-plan-preview-fade')),
      findsOneWidget,
    );

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            plan('# Short transient render', status: 'inProgress'),
          ],
          'pendingRequests': const <Object?>[],
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('codex-plan-preview-fade')),
      findsOneWidget,
    );

    client.emit(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-tab',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            plan('# Short final plan', status: 'completed'),
          ],
          'pendingRequests': const <Object?>[],
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('codex-plan-preview-fade')),
      findsNothing,
    );
  });

  testWidgets('distinguishes numeric and string approval request ids', (
    tester,
  ) async {
    Map<String, Object?> request(Object id, String command) =>
        <String, Object?>{
          'id': id,
          'method': 'item/commandExecution/requestApproval',
          'params': <String, Object?>{'command': command},
        };
    final client = _SurfaceRuntimeClient(
      pendingRequests: <Object?>[
        request(1, 'first-command'),
        request('1', 'second-command'),
      ],
      timelineCells: const <Object?>[],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('first-command'), findsOneWidget);
    expect(find.text('second-command'), findsOneWidget);
  });
}
