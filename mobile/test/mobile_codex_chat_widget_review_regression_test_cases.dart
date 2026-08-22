part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegressionTests() {
  test('mobile raster previews preserve their aspect ratio while bounded', () {
    final preview = mobileCodexRasterPreview(File('/tmp/wide-image.png'));
    final provider = preview.image as ResizeImage;

    expect(provider.width, isNotNull);
    expect(provider.height, isNotNull);
    expect(provider.policy, ResizeImagePolicy.fit);
  });

  test('mobile launches standard external URI schemes', () {
    expect(
      mobileCodexShouldLaunchExternalUri(
        'mailto:user@example.com',
        Uri.parse('mailto:user@example.com'),
      ),
      isTrue,
    );
    expect(
      mobileCodexShouldLaunchExternalUri('tel:+1234', Uri.parse('tel:+1234')),
      isTrue,
    );
    expect(
      mobileCodexShouldLaunchExternalUri('sms:+1234', Uri.parse('sms:+1234')),
      isTrue,
    );
    expect(
      mobileCodexShouldLaunchExternalUri(
        'file:///repo/readme.md',
        Uri.parse('file:///repo/readme.md'),
      ),
      isFalse,
    );
    expect(
      mobileCodexShouldLaunchExternalUri(
        r'C:\repo\readme.md',
        Uri.parse('C:/repo/readme.md'),
      ),
      isFalse,
    );
  });

  test(
    'mobile plan sharing converts platform failures into a result',
    () async {
      final shared = await shareMobileCodexPlanText(
        '# Plan',
        sharePositionOrigin: const Rect.fromLTWH(10, 20, 30, 40),
        share: (_) => Future<ShareResult>.error(StateError('unavailable')),
      );

      expect(shared, isFalse);
    },
  );

  testWidgets('mobile expanded plans retain workspace link scope', (
    tester,
  ) async {
    final reads = <String>[];
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['README.md'],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'plan-with-link',
          'kind': 'plan',
          'status': 'completed',
          'title': 'Plan',
          'markdownText': '[README.md](README.md:1)',
        },
      ],
      workspaceFileReader: (workspaceId, relativePath, cwd, offset, length) {
        reads.add(relativePath);
        return Future<MobileWorkspaceFileRange>.value(
          const MobileWorkspaceFileRange(
            relativePath: 'README.md',
            offset: 0,
            nextOffset: 6,
            totalBytes: 6,
            mimeType: 'text/markdown',
            isText: true,
            bytes: <int>[82, 69, 65, 68, 77, 69],
          ),
        );
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-plan-link');

    await tester.tap(find.byTooltip('Maximize Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('README.md').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(reads, <String>['README.md']);
  });

  testWidgets('mobile leaves unused arrow keys to multiline text editing', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-caret-arrows');
    final composer = find.byType(TextField).last;

    await tester.enterText(composer, 'first line\nsecond line');
    final arrowHandler = tester.widget<Focus>(
      find
          .descendant(
            of: find.byType(CallbackShortcuts),
            matching: find.byWidgetPredicate(
              (widget) => widget is Focus && widget.onKeyEvent != null,
            ),
          )
          .first,
    );
    final eventNode = FocusNode();
    addTearDown(eventNode.dispose);
    final result = arrowHandler.onKeyEvent!(
      eventNode,
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: LogicalKeyboardKey.arrowUp,
        timeStamp: Duration.zero,
      ),
    );

    expect(result, KeyEventResult.ignored);
  });

  testWidgets('mobile resets prompt history after normal draft editing', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'first-user',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'First prompt',
        },
        <String, Object?>{
          'id': 'second-user',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Second prompt',
        },
      ],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-prompt-history');
    final composer = find.byType(TextField).last;
    final controller = tester.widget<TextField>(composer).controller!;

    await tester.tap(composer);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(controller.text, 'Second prompt');

    await tester.enterText(composer, 'Edited draft');
    await tester.enterText(composer, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(controller.text, 'Second prompt');
  });

  testWidgets('mobile re-enables short history pagination responses', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      requestHandler: (type, payload) async {
        if (type == 'codex.thread.open') {
          return <String, Object?>{
            'historyNextCursor': 'older',
            'snapshot': const <String, Object?>{'timelineCells': <Object?>[]},
          };
        }
        if (type == 'codex.thread.history') {
          return <String, Object?>{
            'nextCursor': 'still-older',
            'snapshot': const <String, Object?>{'timelineCells': <Object?>[]},
          };
        }
        return <String, Object?>{};
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-short-history');

    final button = find.widgetWithText(TextButton, 'Load Earlier Messages');
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
  });

  testWidgets('mobile touch send steers while a turn is active', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-active',
        'timelineCells': <Object?>[],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-touch-steer');

    await tester.enterText(find.byType(TextField).last, 'Change direction');
    await tester.pump();
    await tester.tap(find.byTooltip('Steer'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.turn.steer'),
      hasLength(1),
    );
  });

  testWidgets('mobile keeps large interaction forms scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = FakeMobileCodexClient(
      initialSnapshot: <String, Object?>{
        'timelineCells': const <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 91,
            'method': 'mcpServer/elicitation/request',
            'params': <String, Object?>{
              'mode': 'form',
              'requestedSchema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  for (var index = 1; index <= 8; index++)
                    'field$index': <String, Object?>{
                      'type': 'string',
                      'title': 'Field $index',
                    },
                },
              },
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-long-request');

    expect(tester.takeException(), isNull);
    final dockScroll = find.ancestor(
      of: find.text('MCP Server Needs Input'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(dockScroll, findsOneWidget);
    await tester.drag(dockScroll, const Offset(0, -400));
    await tester.pump();
    expect(find.text('Field 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile hides auto review on legacy turn policy hosts', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      supportsCodexTurnPolicy: false,
      configuration: <String, Object?>{'permissionMode': 'auto-review'},
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-legacy-policy');

    expect(find.text('Ask Approval'), findsOneWidget);
    await tester.tap(find.text('Ask Approval'));
    await tester.pumpAndSettle();

    expect(find.text('Approve For Me'), findsNothing);
    expect(find.text('Ask For Approval'), findsOneWidget);
    expect(find.text('Full Access'), findsOneWidget);
  });

  testWidgets('mobile compact command executes locally from touch send', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-compact-command');

    await tester.enterText(find.byType(TextField).last, '/compact');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.type == 'codex.thread.compact'),
      hasLength(1),
    );
    expect(
      client.calls.where((call) => call.type == 'codex.turn.start'),
      isEmpty,
    );
  });

  testWidgets('mobile keeps visible history anchored when prepending rows', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      requestHandler: (type, payload) async {
        if (type == 'codex.thread.open') {
          return <String, Object?>{
            'threadId': 'thread-history-anchor',
            'historyNextCursor': 'older',
            'snapshot': <String, Object?>{
              'timelineCells': <Object?>[
                for (var index = 0; index < 20; index++)
                  <String, Object?>{
                    'id': 'recent-$index',
                    'kind': 'assistantMessage',
                    'status': 'completed',
                    'markdownText':
                        'Recent message $index with enough content.',
                  },
              ],
            },
          };
        }
        if (type == 'codex.thread.history') {
          return <String, Object?>{
            'snapshot': <String, Object?>{
              'timelineCells': <Object?>[
                for (var index = 0; index < 20; index++)
                  <String, Object?>{
                    'id': 'older-$index',
                    'kind': 'assistantMessage',
                    'status': 'completed',
                    'markdownText': 'Older message $index with enough content.',
                  },
              ],
            },
          };
        }
        return <String, Object?>{};
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-history-anchor');
    final scroll = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final anchorKey = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'cell-recent-',
              ),
        )
        .evaluate()
        .map((element) => element.widget.key! as ValueKey<String>)
        .first;
    final anchor = find.byKey(anchorKey);
    final topBefore = tester.getTopLeft(anchor).dy;

    expect(scroll.controller!.offset, 0);
    await tester.tap(find.text('Load Earlier Messages'));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(anchor).dy, closeTo(topBefore, 1));
    expect(find.text('Recent message 0 with enough content.'), findsWidgets);
  });

  testWidgets('mobile preserves collaboration mode selection', (tester) async {
    final client = FakeMobileCodexClient(
      responses: const <String, Map<String, Object?>>{
        'codex.collaborationModes.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'mode': 'default'},
            <String, Object?>{'mode': 'plan'},
            <String, Object?>{'mode': 'pair-programming'},
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-collaboration');

    await tester.tap(find.textContaining('Current Codex'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.text('Pair programming'));
    await tester.pump();

    expect(client.configuration?['collaborationMode'], 'pair-programming');
  });

  testWidgets('mobile queued messages remain editable', (tester) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-active',
        'timelineCells': <Object?>[],
      },
    );
    final container = ProviderContainer(
      overrides: [
        mobileCodexClientProvider(
          'host-queue-edit',
        ).overrideWith((ref) async => client),
      ],
    );
    addTearDown(() {
      client.dispose();
      container.dispose();
    });
    await _pumpScreen(
      tester,
      client: client,
      hostId: 'host-queue-edit',
      container: container,
    );
    await container
        .read(
          mobileCodexControllerProvider(
            'host-queue-edit',
            'tab-host-queue-edit',
          ).notifier,
        )
        .send('Original queued text');
    await tester.pump();

    await tester.tap(find.widgetWithText(InputChip, 'Original queued text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Edited queued text');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edited queued text'), findsOneWidget);
    expect(find.text('Original queued text'), findsNothing);
  });
}
