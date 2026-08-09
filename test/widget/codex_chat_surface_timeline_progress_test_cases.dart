part of 'codex_chat_surface_test.dart';

void registerCodexTimelineProgressTests() {
  testWidgets('derives active plan progress only from the live window', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      activeTurnId: 'turn-active',
      historyNextCursor: 'older',
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'live-message',
          'turnId': 'turn-active',
          'kind': 'assistantMessage',
          'status': 'inProgress',
          'markdownText': 'Working on the active turn',
        },
      ],
      historyTimelineCells: const <Object?>[
        <String, Object?>{
          'id': 'historical-plan',
          'turnId': 'turn-active',
          'kind': 'plan',
          'status': 'inProgress',
          'metadata': <String, Object?>{
            'plan': <Object?>[
              <String, Object?>{
                'step': 'Historical step',
                'status': 'inProgress',
              },
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pumpAndSettle();

    expect(find.text('Historical step'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('codex-plan-progress-dock')),
      findsNothing,
    );
  });

  testWidgets('scrolls a plan progress card with many wrapped steps', (
    tester,
  ) async {
    final steps = <Object?>[
      for (var index = 1; index <= 30; index += 1)
        <String, Object?>{
          'step':
              'Step $index with enough detail to wrap inside the progress card',
          'status': index == 1 ? 'inProgress' : 'pending',
        },
    ];
    final client = _SurfaceRuntimeClient(
      activeTurnId: 'turn-plan',
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[
        <String, Object?>{
          'id': 'active-plan',
          'turnId': 'turn-plan',
          'kind': 'plan',
          'status': 'inProgress',
          'metadata': <String, Object?>{'plan': steps},
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, height: 360);

    final trigger = find.byKey(const ValueKey<String>('codex-plan-progress'));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: tester.getCenter(trigger));
    await pointer.moveTo(tester.getCenter(trigger));
    await tester.pump(AleraTokens.durationFast);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final progressList = find.byKey(
      const ValueKey<String>('codex-plan-progress-list'),
    );
    expect(progressList, findsOneWidget);
    expect(find.textContaining('Step 30 with enough detail'), findsNothing);

    await tester.scrollUntilVisible(
      find.textContaining('Step 30 with enough detail'),
      AleraTokens.codexPlanProgressMaxHeight,
      scrollable: find.descendant(
        of: progressList,
        matching: find.byType(Scrollable),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Step 30 with enough detail'), findsOneWidget);
  });

  testWidgets('keeps one plan flight animation across streamed rebuilds', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      activeTurnId: 'turn-plan',
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'plan',
          'turnId': 'turn-plan',
          'kind': 'plan',
          'status': 'inProgress',
          'markdownText': '# Plan',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    await tester.tap(find.byTooltip('Maximize Plan'));
    await tester.pumpAndSettle();
    for (var update = 1; update <= 20; update += 1) {
      client.emit(
        RuntimeHostEvent('codexThreadChanged', <String, Object?>{
          'tabId': 'codex-tab',
          'snapshotDelta': <String, Object?>{
            'timelineUpserts': <Object?>[
              <String, Object?>{
                'id': 'plan',
                'turnId': 'turn-plan',
                'kind': 'plan',
                'status': 'inProgress',
                'markdownText': '# Plan\n\nUpdate $update',
              },
            ],
          },
        }),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('codex-plan-card-maximized')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Restore Plan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('counts every file represented by an aggregated diff cell', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      activeTurnId: 'turn-diff',
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'diff',
          'turnId': 'turn-diff',
          'kind': 'diff',
          'status': 'completed',
          'metadata': <String, Object?>{
            'changes': <Object?>[
              <String, Object?>{'path': 'one.dart'},
              <String, Object?>{'path': 'two.dart'},
              <String, Object?>{'path': 'three.dart'},
            ],
          },
        },
        <String, Object?>{
          'id': 'command',
          'turnId': 'turn-diff',
          'kind': 'command',
          'status': 'completed',
          'title': 'dart analyze',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    expect(find.text('Edited 3 files, ran 1 command'), findsOneWidget);
  });

  testWidgets('preserves the viewport anchor when history is prepended', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      supportsSessions: true,
      historyNextCursor: 'older',
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[
        for (var index = 0; index < 30; index += 1)
          <String, Object?>{
            'id': 'current-$index',
            'turnId': 'current-turn-$index',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Current message $index',
          },
      ],
      historyTimelineCells: <Object?>[
        for (var index = 0; index < 10; index += 1)
          <String, Object?>{
            'id': 'older-$index',
            'turnId': 'older-turn-$index',
            'kind': 'assistantMessage',
            'status': 'completed',
            'markdownText': 'Older message $index',
          },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client, height: 400);

    final timeline = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey<String>('codex-timeline-scroll-view')),
    );
    final controller = timeline.controller!;
    final previousMaxScrollExtent = controller.position.maxScrollExtent;
    controller.jumpTo(AleraTokens.space24);
    await tester.pump();
    await tester.pumpAndSettle();

    final prependedExtent =
        controller.position.maxScrollExtent - previousMaxScrollExtent;
    expect(prependedExtent, greaterThan(0));
    expect(
      controller.position.pixels,
      closeTo(AleraTokens.space24 + prependedExtent, AleraTokens.space2),
    );
    expect(find.text('Older message 0'), findsNothing);
    expect(find.text('Current message 0'), findsWidgets);
  });

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
  });

  testWidgets('fades only plan previews that overflow', (tester) async {
    Map<String, Object?> plan(String markdown) => <String, Object?>{
      'id': 'plan-preview',
      'kind': 'plan',
      'status': 'completed',
      'markdownText': markdown,
    };

    final client = _SurfaceRuntimeClient(
      pendingRequests: const <Object?>[],
      timelineCells: <Object?>[plan('# Short plan')],
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
            plan(List<String>.filled(40, 'Long plan line').join('\n\n')),
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
