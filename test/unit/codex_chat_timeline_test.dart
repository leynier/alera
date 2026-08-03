import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _message(String method, Map<String, Object?> params) =>
    <String, Object?>{'method': method, 'params': params};

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);

  test('coalesces progressive assistant deltas by item id', () {
    var cells = <CodexTimelineCell>[];
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('turn/started', <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'answer-1',
        'delta': 'Hello',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'answer-1',
        'delta': ' world',
      }),
      now: now,
    );
    expect(cells, hasLength(2));
    final answer = cells.singleWhere((cell) => cell.itemId == 'answer-1');
    expect(answer.kind, CodexTimelineKind.assistantMessage);
    expect(answer.markdownText, 'Hello world');
    expect(answer.isStreaming, isTrue);
  });

  test(
    'keeps commentary, reasoning, command output, diff, plan and subagent rows distinct',
    () {
      var cells = <CodexTimelineCell>[];
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/agentMessage/delta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'commentary-1',
          'phase': 'commentary',
          'delta': 'Inspecting files',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/reasoning/textDelta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'reason-1',
          'delta': 'Checking the plan',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/started', <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'command-1',
            'type': 'commandExecution',
            'command': 'git status',
          },
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/commandExecution/outputDelta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'command-1',
          'delta': 'clean',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('turn/diff/updated', <String, Object?>{
          'turnId': 'turn-1',
          'diff': 'diff --git a/file b/file',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/started', <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{'id': 'plan-1', 'type': 'plan'},
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/started', <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{'id': 'agent-1', 'type': 'subAgent'},
        }),
        now: now,
      );
      expect(
        cells.map((cell) => cell.kind),
        containsAll(<CodexTimelineKind>[
          CodexTimelineKind.progressText,
          CodexTimelineKind.reasoning,
          CodexTimelineKind.command,
          CodexTimelineKind.diff,
          CodexTimelineKind.plan,
          CodexTimelineKind.subAgent,
        ]),
      );
      expect(
        cells.singleWhere((cell) => cell.itemId == 'command-1').detailsText,
        'clean',
      );
    },
  );

  test('replaces full diff snapshots instead of appending them', () {
    final first = CodexTimelineReducer.reduce(
      const <CodexTimelineCell>[],
      _message('turn/diff/updated', <String, Object?>{
        'turnId': 'turn-1',
        'diff': 'first snapshot',
      }),
      now: now,
    );
    final second = CodexTimelineReducer.reduce(
      first,
      _message('turn/diff/updated', <String, Object?>{
        'turnId': 'turn-1',
        'diff': 'second snapshot',
      }),
      now: now,
    );
    expect(
      second.singleWhere((cell) => cell.id == 'diff-turn-1').detailsText,
      'second snapshot',
    );
  });

  test('turn completion closes every streaming cell and marks failures', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'answer-1',
        'delta': 'partial',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('turn/failed', <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      }),
      now: now,
    );
    expect(cells.single.status, CodexTimelineStatus.failed);
    expect(cells.single.isStreaming, isFalse);
  });

  test('maps standalone command and file streams to specific kinds', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('item/commandExecution/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'command-1',
        'delta': 'done',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/fileChange/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'files-1',
        'delta': 'diff',
      }),
      now: now,
    );
    expect(
      cells.singleWhere((cell) => cell.itemId == 'command-1').kind,
      CodexTimelineKind.command,
    );
    expect(
      cells.singleWhere((cell) => cell.itemId == 'files-1').kind,
      CodexTimelineKind.diff,
    );
  });

  test('restores legacy item completion and task messages', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('codex/event/item_started', <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-1',
          'item': <String, Object?>{'id': 'answer-1', 'type': 'agentMessage'},
        },
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('codex/event/task_complete', <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-1',
          'last_agent_message': 'done',
        },
      }),
      now: now,
    );
    final answer = cells.singleWhere((cell) => cell.id == 'assistant-turn-1');
    expect(answer.kind, CodexTimelineKind.assistantMessage);
    expect(answer.markdownText, 'done');
    expect(answer.isStreaming, isFalse);
  });

  test('preserves commentary phase and de-duplicates repeated output', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('codex/event/item_started', <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-1',
          'item': <String, Object?>{
            'id': 'commentary-1',
            'type': 'AgentMessage',
            'phase': 'commentary',
          },
        },
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'commentary-1',
        'delta': 'Inspecting files',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/commandExecution/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'command-1',
        'delta': 'clean',
      }),
      now: now,
    );
    final repeated = CodexTimelineReducer.reduce(
      cells,
      _message('item/commandExecution/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'command-1',
        'delta': 'clean',
      }),
      now: now,
    );
    expect(
      repeated.singleWhere((cell) => cell.itemId == 'commentary-1').kind,
      CodexTimelineKind.progressText,
    );
    expect(
      repeated.singleWhere((cell) => cell.itemId == 'command-1').detailsText,
      'clean',
    );
    expect(repeated, hasLength(cells.length));
  });

  test('parses structured questions and session approval actions', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'pendingRequests': <Object?>[
        <String, Object?>{
          'id': 7,
          'method': 'item/tool/request_user_input',
          'params': <String, Object?>{
            'questions': <Object?>[
              <String, Object?>{
                'id': 'mode',
                'header': 'Mode',
                'question': 'How should I proceed?',
                'options': <Object?>[
                  <String, Object?>{'label': 'Fast'},
                  <String, Object?>{'label': 'Careful'},
                ],
              },
            ],
          },
        },
        <String, Object?>{
          'id': 8,
          'method': 'item/commandExecution/requestApproval',
          'params': <String, Object?>{'command': 'git status'},
        },
      ],
    });
    expect(snapshot.pendingRequests[0].isQuestion, isTrue);
    expect(snapshot.pendingRequests[0].questions.single.options, hasLength(2));
    expect(snapshot.pendingRequests[1].isApproval, isTrue);
    expect(snapshot.pendingRequests[1].approvalDescription, 'git status');
  });

  test('restores legacy raw events into durable timeline cells', () {
    final snapshot = CodexChatSnapshot.fromJson(<String, Object?>{
      'events': <Object?>[
        _message('item/agentMessage/delta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'answer-1',
          'delta': 'restored',
        }),
      ],
    });
    expect(snapshot.timelineCells.single.markdownText, 'restored');
    expect(snapshot.toJson()['timelineCells'], isA<List<Object?>>());
  });

  test(
    'model metadata preserves supported reasoning and fast-mode behavior',
    () {
      final model = CodexModelOption.fromJson(<String, Object?>{
        'id': 'gpt-current',
        'displayName': 'Current Codex',
        'isDefault': true,
        'contextWindowTokens': 128000,
        'supportsFastMode': true,
        'reasoningEfforts': <String>['medium', 'high'],
      });
      expect(model.isDefault, isTrue);
      expect(model.contextWindowTokens, 128000);
      expect(model.reasoningEfforts, <String>['medium', 'high']);
      expect(model.supportsFastMode, isTrue);
    },
  );
}
