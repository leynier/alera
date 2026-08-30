part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexRequestTests() {
  testWidgets('mobile resets question state when the request changes', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 31,
            'method': 'item/tool/request_user_input',
            'params': <String, Object?>{
              'questions': <Object?>[
                <String, Object?>{'id': 'first', 'question': 'First question'},
                <String, Object?>{
                  'id': 'second',
                  'question': 'Second question',
                },
              ],
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-question-replace');

    await tester.tap(find.byTooltip('Next Question'));
    await tester.pump();
    expect(find.text('Second question'), findsWidgets);

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-question-replace',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[
            <String, Object?>{
              'id': 32,
              'method': 'item/tool/request_user_input',
              'params': <String, Object?>{
                'questions': <Object?>[
                  <String, Object?>{
                    'id': 'replacement',
                    'question': 'Replacement question',
                  },
                ],
              },
            },
          ],
        },
      }),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Replacement question'), findsWidgets);
  });

  testWidgets('mobile resets elicitation fields when the request changes', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      initialSnapshot: const <String, Object?>{
        'timelineCells': <Object?>[],
        'pendingRequests': <Object?>[
          <String, Object?>{
            'id': 41,
            'method': 'mcpServer/elicitation/request',
            'params': <String, Object?>{
              'mode': 'form',
              'requestedSchema': <String, Object?>{
                'type': 'object',
                'properties': <String, Object?>{
                  'first': <String, Object?>{
                    'type': 'string',
                    'title': 'First Value',
                  },
                },
              },
            },
          },
        ],
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-form-replace');

    await tester.enterText(
      find.widgetWithText(TextField, 'First Value'),
      'stale value',
    );
    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-form-replace',
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[
            <String, Object?>{
              'id': 42,
              'method': 'mcpServer/elicitation/request',
              'params': <String, Object?>{
                'mode': 'form',
                'requestedSchema': <String, Object?>{
                  'type': 'object',
                  'properties': <String, Object?>{
                    'second': <String, Object?>{
                      'type': 'string',
                      'title': 'Second Value',
                    },
                  },
                },
              },
            },
          ],
        },
      }),
    );
    await tester.pump();

    expect(find.widgetWithText(TextField, 'First Value'), findsNothing);
    final replacement = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Second Value'),
    );
    expect(replacement.controller?.text, isEmpty);
  });

  testWidgets('mobile timeline lazily builds a bounded visible slice', (
    tester,
  ) async {
    final cells = <Object?>[
      for (var index = 0; index < 500; index++)
        <String, Object?>{
          'id': 'long-$index',
          'kind': index.isEven ? 'userMessage' : 'assistantMessage',
          'status': 'completed',
          'turnId': 'turn-${index ~/ 2}',
          'markdownText': 'Long timeline message $index',
        },
    ];
    final client = FakeMobileCodexClient(timelineCells: cells);
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-long');
    final builtRows = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('cell-long-'),
        )
        .evaluate()
        .length;
    expect(builtRows, greaterThan(0));
    expect(builtRows, lessThan(cells.length));
  });

  testWidgets('mobile timeline follows streamed rows while pinned to bottom', (
    tester,
  ) async {
    final cells = <Object?>[
      for (var index = 0; index < 40; index++)
        <String, Object?>{
          'id': 'stream-$index',
          'kind': 'assistantMessage',
          'status': 'completed',
          'turnId': 'turn-stream',
          'markdownText': 'Timeline message $index with enough text to scroll.',
        },
    ];
    final client = FakeMobileCodexClient(timelineCells: cells);
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-stream-pin');

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final scrollController = scrollView.controller!;
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();

    client.emit(
      const MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-stream-pin',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'stream-latest',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'turnId': 'turn-stream',
              'markdownText': 'Latest streamed message with enough text to extend the timeline.',
              'isStreaming': true,
            },
          ],
          'timelineRemovedIds': <Object?>[],
          'eventsAppend': <Object?>[],
          'activeTurnId': 'turn-stream',
        },
      }),
    );
    await tester.pump();
    await tester.pump();

    expect(
      scrollController.position.pixels,
      greaterThanOrEqualTo(scrollController.position.maxScrollExtent),
    );

    client.emit(
      MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-stream-pin',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'stream-latest',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'turnId': 'turn-stream',
              'markdownText': List<String>.filled(
                24,
                'A streamed line that increases the final cell height.',
              ).join('\n\n'),
              'isStreaming': true,
            },
          ],
          'timelineRemovedIds': const <Object?>[],
          'eventsAppend': const <Object?>[],
          'activeTurnId': 'turn-stream',
        },
      }),
    );
    await tester.pump();
    await tester.pump();

    expect(scrollController.position.extentAfter, lessThan(AleraTokens.space2));
  });

  testWidgets('mobile stops following after the user scrolls away', (
    tester,
  ) async {
    final cells = <Object?>[
      for (var index = 0; index < 40; index++)
        <String, Object?>{
          'id': 'interrupt-$index',
          'kind': 'assistantMessage',
          'status': 'completed',
          'turnId': 'turn-interrupt',
          'markdownText': 'Timeline message $index with enough text to scroll.',
        },
      <String, Object?>{
        'id': 'interrupt-latest',
        'kind': 'assistantMessage',
        'status': 'inProgress',
        'turnId': 'turn-interrupt',
        'markdownText': 'Short streaming response',
        'isStreaming': true,
      },
    ];
    final client = FakeMobileCodexClient(timelineCells: cells);
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-stream-interrupt');

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final scrollController = scrollView.controller!;
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();

    client.emit(
      MobileRuntimeEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'tab-host-stream-interrupt',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'interrupt-latest',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'turnId': 'turn-interrupt',
              'markdownText': List<String>.filled(
                48,
                'A streamed line that increases the final cell height.',
              ).join('\n\n'),
              'isStreaming': true,
            },
          ],
          'timelineRemovedIds': const <Object?>[],
          'eventsAppend': const <Object?>[],
          'activeTurnId': 'turn-interrupt',
        },
      }),
    );
    await tester.pump();

    final userOffset = (scrollController.position.maxScrollExtent - 300).clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );
    scrollController.jumpTo(userOffset);
    await tester.pump();
    await tester.pump();

    expect(scrollController.position.pixels, closeTo(userOffset, 1));
    expect(
      scrollController.position.extentAfter,
      greaterThan(AleraTokens.space48),
    );
  });

  testWidgets('mobile renders generic attachments as timeline chips', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'user-with-file',
          'kind': 'userMessage',
          'status': 'completed',
          'turnId': 'turn-file',
          'markdownText': 'Y este?',
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
    await _pumpScreen(tester, client: client, hostId: 'host-file');

    expect(find.text('Y este?'), findsOneWidget);
    expect(find.text('data.csv'), findsOneWidget);
    expect(find.textContaining('Attachments Files:'), findsNothing);
    expect(find.text('/tmp/data.csv'), findsNothing);
  });

  testWidgets('mobile attachment viewer preserves the original file name', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['workspace-capability-marker'],
      timelineCells: const <Object?>[
        <String, Object?>{
          'id': 'user-with-upload',
          'kind': 'userMessage',
          'status': 'completed',
          'turnId': 'turn-upload',
          'markdownText': 'Review it',
          'metadata': <String, Object?>{
            'attachments': <Object?>[
              <String, Object?>{
                'path': '/tmp/prompt-files/9fd2fda7',
                'displayName': 'quarterly-report.csv',
                'kind': 'file',
              },
            ],
          },
        },
      ],
      workspaceFileReader:
          (workspaceId, relativePath, cwd, offset, length) async {
            return const MobileWorkspaceFileRange(
              relativePath: '9fd2fda7',
              offset: 0,
              nextOffset: 4,
              totalBytes: 4,
              mimeType: 'text/csv',
              isText: true,
              bytes: <int>[97, 44, 98, 10],
            );
          },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-upload-name');

    await tester.tap(find.text('quarterly-report.csv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.widgetWithText(AppBar, 'quarterly-report.csv'), findsOneWidget);
    expect(find.text('9fd2fda7'), findsNothing);
  });

  testWidgets('mobile keeps @ workspace paths visible and sends them inline', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/my notes.md'],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mention');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@notes');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('docs/my notes.md'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(composer).controller!.text,
      '"docs/my notes.md" ',
    );
    final chip = tester.widget<InputChip>(find.byType(InputChip));
    expect((chip.avatar! as Icon).icon, Icons.description_outlined);

    await tester.tap(composer);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final turn = client.calls.lastWhere(
      (call) => call.type == 'codex.turn.start',
    );
    expect(turn.payload['input'], <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text': '"docs/my notes.md"',
        'text_elements': <Map<String, Object?>>[
          <String, Object?>{
            'byteRange': <String, Object?>{'start': 0, 'end': 18},
            'placeholder': 'my notes.md',
          },
        ],
      },
    ]);
    expect(turn.payload['userMessage'], <String, Object?>{
      'text': '"docs/my notes.md"',
      'attachments': <Map<String, Object?>>[
        <String, Object?>{
          'path': 'docs/my notes.md',
          'displayName': 'my notes.md',
          'kind': 'file',
          'origin': 'mention',
          'isImage': false,
          'isDirectory': false,
        },
      ],
    });
  });
}
