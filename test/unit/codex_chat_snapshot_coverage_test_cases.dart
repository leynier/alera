part of 'codex_chat_models_coverage_test.dart';

void registerCodexSnapshotCoverageTests(DateTime now) {
  test('snapshot deltas preserve unchanged cells and derived history', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'user',
          'kind': 'userMessage',
          'markdownText': 'First prompt',
        },
        <String, Object?>{
          'id': 'stable',
          'kind': 'assistantMessage',
          'markdownText': 'Stable response',
        },
        <String, Object?>{
          'id': 'stream',
          'kind': 'assistantMessage',
          'markdownText': 'One',
        },
      ],
      'pendingRequests': <Object?>[
        <String, Object?>{'id': 1, 'method': 'request'},
      ],
      'activeTurnId': 'turn-1',
    });
    final stable = snapshot.timelineCells[1];
    final pending = snapshot.pendingRequests;
    final history = snapshot.promptHistory;

    final updated = snapshot.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'stream',
          'kind': 'assistantMessage',
          'markdownText': 'One two',
        },
      ],
      'timelineRemovedIds': const <Object?>[],
      'eventsAppend': <Object?>[
        <String, Object?>{'method': 'item/agentMessage/delta'},
      ],
      'eventLimit': 160,
      'activeTurnId': null,
      'contextUsed': 42,
    });

    expect(identical(updated.timelineCells[1], stable), isTrue);
    expect(updated.timelineCells[2].markdownText, 'One two');
    expect(identical(updated.pendingRequests, pending), isTrue);
    expect(identical(updated.promptHistory, history), isTrue);
    expect(updated.activeTurnId, isNull);
    expect(updated.contextUsed, 42);
    expect(updated.events, hasLength(1));

    final withSecondPrompt = updated.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'user-2',
          'kind': 'userMessage',
          'markdownText': 'Second prompt',
        },
      ],
    });
    expect(withSecondPrompt.promptHistory, <String>[
      'First prompt',
      'Second prompt',
    ]);
  });

  test(
    'snapshot deltas preserve absent fields and normalize explicit ones',
    () {
      final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
        'events': <Object?>[
          <String, Object?>{'method': 'existing'},
        ],
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'user',
            'kind': 'userMessage',
            'markdownText': 'Keep this prompt',
          },
        ],
        'pendingRequests': <Object?>[
          <String, Object?>{'id': 1, 'method': 'request'},
        ],
        'activeTurnId': 'turn-1',
        'contextUsed': 10,
        'contextLimit': 20,
        'title': 'Existing title',
        'goal': <String, Object?>{
          'threadId': 'thread-1',
          'objective': 'Existing goal',
          'status': 'active',
          'tokensUsed': 3,
          'timeUsedSeconds': 4,
        },
      });

      expect(identical(snapshot.applyDelta(null), snapshot), isTrue);
      expect(
        identical(snapshot.applyDelta(const <String, Object?>{}), snapshot),
        isTrue,
      );

      final partial = snapshot.applyDelta(<String, Object?>{
        'timelineRemovedIds': <Object?>[null, ''],
        'timelineUpserts': <Object?>['ignored'],
        'eventsAppend': 'ignored',
        'contextUsed': '42',
      });
      expect(identical(partial.timelineCells, snapshot.timelineCells), isTrue);
      expect(identical(partial.events, snapshot.events), isTrue);
      expect(identical(partial.promptHistory, snapshot.promptHistory), isTrue);
      expect(
        identical(partial.pendingRequests, snapshot.pendingRequests),
        isTrue,
      );
      expect(identical(partial.goal, snapshot.goal), isTrue);
      expect(partial.activeTurnId, 'turn-1');
      expect(partial.contextUsed, 42);
      expect(partial.contextLimit, 20);
      expect(partial.title, 'Existing title');

      final cleared = partial.applyDelta(<String, Object?>{
        'pendingRequests': null,
        'activeTurnId': null,
        'contextUsed': 'invalid',
        'contextLimit': null,
        'title': 7,
        'goal': 'invalid',
      });
      expect(cleared.pendingRequests, isEmpty);
      expect(cleared.activeTurnId, isNull);
      expect(cleared.contextUsed, isNull);
      expect(cleared.contextLimit, isNull);
      expect(cleared.title, isNull);
      expect(cleared.goal, isNull);

      final withPartialGoal = cleared.applyDelta(<String, Object?>{
        'goal': <String, Object?>{'objective': 'Replacement goal'},
      });
      expect(withPartialGoal.goal?.objective, 'Replacement goal');
      expect(withPartialGoal.goal?.threadId, isEmpty);

      expect(
        () => snapshot.applyDelta(<String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{'kind': 'assistantMessage'},
          ],
        }),
        throwsFormatException,
      );
    },
  );

  test('snapshot deltas share expanded history while updating live cells', () {
    CodexTimelineCell cell(String id, String text) =>
        CodexTimelineCell.fromJson(<String, Object?>{
          'id': id,
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': text,
        });
    final timeline = CodexTimelineCells.segmented(
      history: <CodexTimelineCell>[
        for (var index = 0; index < 1000; index++)
          cell('history-$index', 'History $index'),
      ],
      live: <CodexTimelineCell>[cell('live', 'One')],
    );
    final snapshot = CodexChatSnapshot(timelineCells: timeline);

    final updated = snapshot.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'live',
          'kind': 'assistantMessage',
          'status': 'inProgress',
          'isStreaming': true,
          'markdownText': 'One two',
        },
      ],
    });

    final updatedTimeline = updated.timelineCells as CodexTimelineCells;
    expect(identical(updatedTimeline.history, timeline.history), isTrue);
    expect(updatedTimeline.length, 1001);
    expect(updatedTimeline.last.markdownText, 'One two');
  });

  test('snapshot deltas replace raw events after host byte eviction', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'events': <Object?>[
        <String, Object?>{'method': 'old'},
      ],
    });

    final next = snapshot.applyDelta(<String, Object?>{
      'eventsAppend': <Object?>[
        <String, Object?>{'method': 'large'},
      ],
      'eventsReplace': <Object?>[
        <String, Object?>{'method': 'retained'},
      ],
    });

    expect(next.events, hasLength(1));
    expect(next.events.single.method, 'retained');
  });

  test('snapshot tracks MCP initialization across timeline deltas', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'mcp-startup-filesystem',
          'kind': 'toolCall',
          'status': 'inProgress',
          'isStreaming': true,
          'metadata': <String, Object?>{'itemType': 'mcpServerStartup'},
        },
      ],
    });
    expect(snapshot.mcpInitializing, isTrue);

    final ready = snapshot.applyDelta(<String, Object?>{
      'timelineUpserts': <Object?>[
        <String, Object?>{
          'id': 'mcp-startup-filesystem',
          'kind': 'toolCall',
          'status': 'completed',
          'isStreaming': false,
          'metadata': <String, Object?>{
            'itemType': 'mcpServerStartup',
            'status': 'ready',
          },
        },
      ],
    });
    expect(ready.mcpInitializing, isFalse);

    final removed = snapshot.applyDelta(<String, Object?>{
      'timelineRemovedIds': <Object?>['mcp-startup-filesystem'],
    });
    expect(removed.timelineCells, isEmpty);
    expect(removed.mcpInitializing, isFalse);
  });

  test('recognizes plan questions and separates recommended option labels', () {
    final request = CodexPendingRequest.fromJson(<String, Object?>{
      'id': 9,
      'method': 'item/tool/request_user_input',
      'params': <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{
            'id': 'implement',
            'question': 'Implement this plan?',
            'options': <Object?>[
              <String, Object?>{'label': 'Yes (Recommended)'},
            ],
          },
        ],
      },
    });

    expect(request.isImplementPlanQuestion, isTrue);
    expect(request.questions.single.options.single.isRecommended, isTrue);
    expect(request.questions.single.options.single.displayLabel, 'Yes');

    final planningQuestion = CodexPendingRequest.fromJson(<String, Object?>{
      'id': 10,
      'method': 'item/tool/request_user_input',
      'params': <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{
            'id': 'priority',
            'question': 'Which part of the plan should we implement first?',
          },
        ],
      },
    });
    expect(planningQuestion.isImplementPlanQuestion, isFalse);

    final confirmationVariant = CodexPendingRequest.fromJson(<String, Object?>{
      'id': 11,
      'method': 'item/tool/request_user_input',
      'params': <String, Object?>{
        'questions': <Object?>[
          <String, Object?>{
            'id': 'implement',
            'question': 'Would you like me to implement this plan?',
          },
        ],
      },
    });
    expect(confirmationVariant.isImplementPlanQuestion, isTrue);

    final splitConfirmation = CodexPendingRequest.fromJson(<String, Object?>{
      'id': 12,
      'method': 'item/tool/request_user_input',
      'params': <String, Object?>{
        'title': 'Would you like me to',
        'question': 'implement this plan?',
      },
    });
    expect(splitConfirmation.isImplementPlanQuestion, isTrue);
  });

  test('Codex settings and tab payload getters round-trip typed values', () {
    final settings = CodexChatSettings.fromJson(<String, Object?>{
      'selectedModel': 'gpt-current',
      'reasoningEffort': 'high',
      'speedMode': 'fast',
      'permissionMode': 'never',
      'planMode': true,
    });
    expect(settings.selectedModel, 'gpt-current');
    expect(settings.planMode, isTrue);

    final tab = WorkspaceTabRecord(
      id: 'codex-tab',
      workspaceId: 'workspace',
      kind: .codex,
      title: 'Codex',
      createdAt: now,
      updatedAt: now,
      payload: <String, Object?>{
        workspaceTabCodexThreadIdPayloadKey: 'thread-1',
        workspaceTabCodexActiveTurnIdPayloadKey: 'turn-1',
        workspaceTabCodexSnapshotPayloadKey: <Object?, Object?>{
          'title': 'Chat',
        },
      },
    );
    expect(tab.codexThreadId, 'thread-1');
    expect(tab.codexActiveTurnId, 'turn-1');
    expect(tab.codexSnapshot, <String, Object?>{'title': 'Chat'});

    final empty = WorkspaceTabRecord(
      id: 'empty',
      workspaceId: 'workspace',
      kind: .codex,
      title: 'Codex',
      createdAt: now,
      updatedAt: now,
    );
    expect(empty.codexThreadId, isNull);
    expect(empty.codexActiveTurnId, isNull);
    expect(empty.codexSnapshot, isEmpty);
  });
}
