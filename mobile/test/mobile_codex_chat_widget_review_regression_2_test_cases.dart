part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegression2Tests() {
  testWidgets('mobile can stop while MCP servers are starting', (tester) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'activeTurnId': 'turn-mcp',
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'mcp-startup',
            'kind': 'toolCall',
            'status': 'inProgress',
            'isStreaming': true,
            'metadata': <String, Object?>{'itemType': 'mcpServerStartup'},
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mcp-stop');

    final stop = find.byTooltip('Stop');
    expect(stop, findsOneWidget);
    await tester.tap(stop);
    await tester.pump();

    expect(
      client.calls.where((call) => call.type == 'codex.turn.interrupt'),
      hasLength(1),
    );
  });

  testWidgets(
    'mobile does not submit a saved prompt into a replacement thread',
    (tester) async {
      final prompts = Completer<List<MobileCodexSavedPrompt>>();
      final client = FakeMobileCodexClient(
        savedPromptsLoader: (_, _) => prompts.future,
      );
      final container = ProviderContainer(
        overrides: [
          mobileCodexClientProvider('host-pending-prompt')
              .overrideWith((ref) async => client),
        ],
      );
      addTearDown(() {
        client.dispose();
        container.dispose();
      });
      await _pumpScreen(
        tester,
        client: client,
        hostId: 'host-pending-prompt',
        container: container,
      );

      final composer = find.byType(TextField).last;
      await tester.enterText(composer, '/slow target');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      final controller = container.read(
        mobileCodexControllerProvider(
          'host-pending-prompt',
          'tab-host-pending-prompt',
        ).notifier,
      );
      await controller.newThread();
      prompts.complete(const <MobileCodexSavedPrompt>[
        MobileCodexSavedPrompt(
          name: 'slow',
          description: 'Slow prompt',
          body: r'Expanded $1',
          scope: 'repo',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(
        client.calls.where((call) => call.type == 'codex.turn.start'),
        isEmpty,
      );
      expect(
        tester.widget<TextField>(composer).controller!.text,
        '/slow target',
      );
    },
  );

  testWidgets('mobile retries text previews without dropping earlier chunks', (
    tester,
  ) async {
    var failSecondRange = true;
    final offsets = <int>[];
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['notes.md'],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'retry-link',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': '[notes.md](notes.md#L3)',
        },
      ],
      workspaceFileReader: (workspaceId, relativePath, cwd, offset, length) {
        offsets.add(offset);
        if (offset == 0) {
          return Future.value(
            MobileWorkspaceFileRange(
              relativePath: 'notes.md',
              offset: 0,
              nextOffset: 6,
              totalBytes: 18,
              mimeType: 'text/markdown',
              isText: true,
              bytes: utf8.encode('first\n'),
            ),
          );
        }
        if (failSecondRange) {
          failSecondRange = false;
          return Future.error(StateError('temporary range failure'));
        }
        return Future.value(
          MobileWorkspaceFileRange(
            relativePath: 'notes.md',
            offset: 6,
            nextOffset: 18,
            totalBytes: 18,
            mimeType: 'text/markdown',
            isText: true,
            bytes: utf8.encode('second\nthird'),
          ),
        );
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-preview-retry');

    await tester.tap(find.text('notes.md'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('temporary range failure'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(offsets, <int>[0, 6, 0, 6]);
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
  });

  testWidgets('mobile bounds the footer to the available body height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = FakeMobileCodexClient(
      initialSnapshot: <String, Object?>{
        'timelineCells': const <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 97,
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileCodexClientProvider('host-short-body')
              .overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            appBar: const PreferredSize(
              preferredSize: Size.fromHeight(180),
              child: SizedBox.expand(),
            ),
            body: const MobileCodexChatScreen(
              hostId: 'host-short-body',
              tabId: 'tab-host-short-body',
              workspaceId: 'workspace-host-short-body',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('MCP Server Needs Input'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
