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
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('codex-plan-progress-card')),
          )
          .width,
      AleraTokens.codexPlanProgressCardWidth,
    );
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

  testWidgets('uses circular status icons in plan progress', (tester) async {
    final client = _SurfaceRuntimeClient(
      activeTurnId: 'turn-plan',
      pendingRequests: const <Object?>[],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'active-plan',
          'turnId': 'turn-plan',
          'kind': 'plan',
          'status': 'inProgress',
          'metadata': <String, Object?>{
            'plan': <Object?>[
              <String, Object?>{
                'step': 'Completed step',
                'status': 'completed',
              },
              <String, Object?>{'step': 'Active step', 'status': 'inProgress'},
              <String, Object?>{'step': 'Pending step', 'status': 'pending'},
            ],
          },
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpTimelineSegmentSurface(tester, client);

    final trigger = find.byKey(const ValueKey<String>('codex-plan-progress'));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: tester.getCenter(trigger));
    await pointer.moveTo(tester.getCenter(trigger));
    await tester.pump(AleraTokens.durationFast);
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey<String>('codex-plan-progress-card'));
    expect(
      find.descendant(of: card, matching: find.byIcon(AleraIcons.success)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byIcon(AleraIcons.circle)),
      findsNWidgets(2),
    );
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

  registerCodexTimelineRequestTests();
}
