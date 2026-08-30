import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_preferences.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void mobileCodexStateTests() {
  test('projects goal snapshots and clears them through deltas', () {
    final state = MobileCodexState.fromSnapshot(<String, Object?>{
      'goal': <String, Object?>{
        'threadId': 'thread-1',
        'objective': 'Ship the release',
        'status': 'paused',
        'timeUsedSeconds': 186,
        'updatedAt': 2,
      },
    });

    expect(state.goal?.objective, 'Ship the release');
    expect(state.goal?.status, MobileCodexGoalStatus.paused);
    expect(state.goal?.timeUsedSeconds, 186);
    expect(
      state.applySnapshotDelta(const <String, Object?>{'goal': null}).goal,
      isNull,
    );
    expect(
      MobileCodexGoal.fromJson(state.goal?.toJson()),
      state.goal,
      reason: 'equivalent snapshots should not rebuild the footer',
    );
  });

  test(
    'mobile sharing accepts files above the preview limit within its cap',
    () {
      expect(
        mobileWorkspaceFileCanShare(maxMobileWorkspacePreviewBytes + 1),
        isTrue,
      );
      expect(
        mobileWorkspaceFileCanShare(maxMobileWorkspaceShareBytes + 1),
        isFalse,
      );
    },
  );

  test('mobile derives prompt history and MCP startup from timeline cells', () {
    final state = MobileCodexState.fromSnapshot(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'prompt',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Inspect this',
        },
        <String, Object?>{
          'id': 'steer',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Steer this',
          'metadata': <String, Object?>{'isSteering': true},
        },
        <String, Object?>{
          'id': 'mcp',
          'kind': 'toolCall',
          'status': 'inProgress',
          'isStreaming': true,
          'metadata': <String, Object?>{'itemType': 'mcpServerStartup'},
        },
      ],
    });

    expect(state.promptHistory, <String>['Inspect this']);
    expect(state.mcpInitializing, isTrue);
  });

  test('mobile rebuilds a coherent timeline from legacy raw events', () {
    final state = MobileCodexState.fromSnapshot(<String, Object?>{
      'events': <Object?>[
        <String, Object?>{
          'method': 'turn/started',
          'params': <String, Object?>{
            'turn': <String, Object?>{'id': 'turn-legacy'},
          },
        },
        <String, Object?>{
          'method': 'item/agentMessage/delta',
          'params': <String, Object?>{
            'turnId': 'turn-legacy',
            'itemId': 'answer',
            'delta': 'Hello',
          },
        },
        <String, Object?>{
          'method': 'item/agentMessage/delta',
          'params': <String, Object?>{
            'turnId': 'turn-legacy',
            'itemId': 'answer',
            'delta': ' world',
          },
        },
        <String, Object?>{
          'method': 'turn/completed',
          'params': <String, Object?>{'turnId': 'turn-legacy'},
        },
      ],
    });
    expect(state.timelineCells, hasLength(2));
    expect(state.timelineCells.last.kind, 'assistantMessage');
    expect(state.timelineCells.last.displayText, 'Hello world');
    expect(state.timelineCells.last.isStreaming, isFalse);
  });

  test('mobile replaces full diff snapshots instead of appending them', () {
    var cells = MobileCodexTimelineReducer.reduce(
      const <MobileCodexTimelineCell>[],
      <String, Object?>{
        'method': 'turn/diff/updated',
        'params': <String, Object?>{
          'turnId': 'turn-1',
          'diff': 'first snapshot',
        },
      },
    );
    cells = MobileCodexTimelineReducer.reduce(cells, <String, Object?>{
      'method': 'turn/diff/updated',
      'params': <String, Object?>{
        'turnId': 'turn-1',
        'diff': 'second snapshot',
      },
    });
    expect(
      cells.singleWhere((cell) => cell.id == 'diff-turn-1').detailsText,
      'second snapshot',
    );
  });

  test('mobile exposes only the latest actionable plan', () {
    MobileCodexState state(Object? pendingRequests) =>
        MobileCodexState.fromSnapshot(<String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'user-old',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Old request',
            },
            <String, Object?>{
              'id': 'plan-old',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': 'Old plan',
            },
            <String, Object?>{
              'id': 'user-latest',
              'kind': 'userMessage',
              'status': 'completed',
              'markdownText': 'Latest request',
            },
            <String, Object?>{
              'id': 'plan-latest',
              'kind': 'plan',
              'status': 'completed',
              'markdownText': 'Latest plan',
            },
          ],
          'pendingRequests': pendingRequests,
        });

    expect(state(const <Object?>[]).shouldShowImplementPlan, isTrue);
    expect(
      state(<Object?>[
        <String, Object?>{
          'id': 3,
          'method': 'item/tool/request_user_input',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'plan',
                'question': 'Implement this plan?',
              },
            ],
          },
        },
      ]).shouldShowImplementPlan,
      isFalse,
    );

    final reset = MobileCodexState.fromSnapshot(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'user',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Create a plan',
        },
        <String, Object?>{
          'id': 'plan',
          'kind': 'plan',
          'status': 'completed',
          'markdownText': 'Stale plan',
        },
        <String, Object?>{
          'id': 'reset',
          'kind': 'systemNotice',
          'status': 'info',
          'metadata': <String, Object?>{'noticeType': 'contextReset'},
        },
      ],
    });
    expect(reset.latestActionablePlan, isNull);

    final progressOnly = MobileCodexState.fromSnapshot(<String, Object?>{
      'timelineCells': <Object?>[
        <String, Object?>{
          'id': 'user',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Execute the plan',
        },
        <String, Object?>{
          'id': 'progress',
          'kind': 'plan',
          'status': 'completed',
          'markdownText': 'Execution progress',
          'metadata': <String, Object?>{
            'plan': <Object?>[
              <String, Object?>{'step': 'Build', 'status': 'completed'},
            ],
          },
        },
      ],
    });
    expect(progressOnly.latestActionablePlan, isNull);
    expect(progressOnly.shouldShowImplementPlan, isFalse);
  });

  test(
    'mobile projects warnings first and groups activity only within a turn',
    () {
      final state = MobileCodexState.fromSnapshot(<String, Object?>{
        'activeTurnId': 'turn-2',
        'timelineCells': <Object?>[
          <String, Object?>{
            'id': 'message',
            'kind': 'assistantMessage',
            'status': 'completed',
            'turnId': 'turn-1',
            'markdownText': 'Starting',
          },
          <String, Object?>{
            'id': 'read-1',
            'kind': 'command',
            'status': 'completed',
            'turnId': 'turn-1',
            'title': 'Read file',
          },
          <String, Object?>{
            'id': 'read-2',
            'kind': 'command',
            'status': 'completed',
            'turnId': 'turn-2',
            'title': 'Read another file',
          },
          <String, Object?>{
            'id': 'warning',
            'kind': 'systemNotice',
            'status': 'warning',
            'markdownText': 'Context warning',
          },
          <String, Object?>{
            'id': 'mcp-startup',
            'kind': 'toolCall',
            'status': 'completed',
            'turnId': 'turn-2',
            'title': 'Docs MCP server',
            'metadata': <String, Object?>{'itemType': 'mcpServerStartup'},
          },
        ],
      });
      expect(state.presentationRows.first.cell?.id, 'warning');
      expect(state.presentationRows.first.isTurnActivity, isFalse);
      expect(state.presentationRows[1].cell?.id, 'mcp-startup');
      expect(
        state.presentationRows.where(
          (row) => row.kind == MobileCodexPresentationKind.activity,
        ),
        isEmpty,
      );
      expect(
        state.presentationRows
            .where((row) => row.kind == MobileCodexPresentationKind.working)
            .length,
        1,
      );
      final workingIndex = state.presentationRows.indexWhere(
        (row) => row.kind == MobileCodexPresentationKind.working,
      );
      final activeToolIndex = state.presentationRows.indexWhere(
        (row) => row.cell?.id == 'read-2',
      );
      expect(workingIndex, lessThan(activeToolIndex));
    },
  );

  test('mobile projects a long restored timeline without quadratic growth', () {
    final cells = <MobileCodexTimelineCell>[
      for (var index = 0; index < 10000; index++)
        MobileCodexTimelineCell(
          id: 'cell-$index',
          kind: index.isEven ? 'userMessage' : 'assistantMessage',
          status: 'completed',
          turnId: 'turn-${index ~/ 2}',
          markdownText: 'Timeline message $index',
        ),
    ];
    final stopwatch = Stopwatch()..start();
    final rows = MobileCodexTimelineProjection.project(
      cells,
      activeTurnId: null,
    );
    stopwatch.stop();
    expect(rows, hasLength(cells.length));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('mobile keeps an activity row identity while tools stream into it', () {
    const readOne = MobileCodexTimelineCell(
      id: 'read-one',
      kind: 'command',
      status: 'completed',
      turnId: 'turn-tools',
      title: 'Read one file',
    );
    const readTwo = MobileCodexTimelineCell(
      id: 'read-two',
      kind: 'command',
      status: 'completed',
      turnId: 'turn-tools',
      title: 'Read another file',
    );
    const readThree = MobileCodexTimelineCell(
      id: 'read-three',
      kind: 'command',
      status: 'completed',
      turnId: 'turn-tools',
      title: 'Read a third file',
    );
    const reasoning = MobileCodexTimelineCell(
      id: 'reasoning-before-tools',
      kind: 'reasoning',
      status: 'completed',
      turnId: 'turn-tools',
      markdownText: 'Inspecting the workspace',
    );

    final initial = MobileCodexTimelineProjection.project(
      const <MobileCodexTimelineCell>[readOne, readTwo],
      activeTurnId: 'turn-tools',
    );
    final updated = MobileCodexTimelineProjection.project(
      const <MobileCodexTimelineCell>[reasoning, readOne, readTwo, readThree],
      activeTurnId: 'turn-tools',
    );

    final initialActivity = initial.singleWhere(
      (row) => row.kind == MobileCodexPresentationKind.activity,
    );
    final updatedActivity = updated.singleWhere(
      (row) => row.kind == MobileCodexPresentationKind.activity,
    );
    expect(initialActivity.id, 'activity-read-one');
    expect(updatedActivity.id, initialActivity.id);
  });

  test('mobile identifies only explicit implement-plan decisions', () {
    MobileCodexPendingRequest request(String question) =>
        MobileCodexPendingRequest.fromJson(<String, Object?>{
          'id': 1,
          'method': 'item/tool/request_user_input',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{'id': 'plan', 'question': question},
            ],
          },
        });

    expect(request('Implement this plan?').isImplementPlanQuestion, isTrue);
    expect(
      request('Should I implement the plan now?').isImplementPlanQuestion,
      isTrue,
    );
    expect(
      request('Which plan should implementation prioritize?')
          .isImplementPlanQuestion,
      isFalse,
    );
  });

  test('mobile Codex preferences keep every safe permission mode', () {
    for (final mode in const <String>[
      'untrusted',
      'on-request',
      'auto-review',
      'never',
    ]) {
      final restored = MobileCodexPreferences.fromJson(<String, Object?>{
        'permissionMode': mode,
        'model': 'gpt-test',
      });
      expect(restored.permissionMode, mode);
      expect(restored.toJson()['permissionMode'], mode);
    }
  });
}

void main() => mobileCodexStateTests();
