import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/application/session_timeline_reducer.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

SessionNotificationEvent _event(String method, Map<String, dynamic> params) {
  return SessionNotificationEvent(
    method: method,
    payload: <String, dynamic>{'params': params},
  );
}

List<TimelineCell> _cellsByKind(SessionState state, TimelineCellKind kind) {
  return state.timelineCells
      .where((cell) => cell.kind == kind)
      .toList(growable: false);
}

void main() {
  group('session timeline reducer', () {
    test('newline-gated streaming commits only after newline', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('codex/event/item_started', <String, dynamic>{
          'msg': <String, dynamic>{
            'type': 'item_started',
            'turn_id': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-1',
              'type': 'AgentMessage',
              'phase': 'final_answer',
            },
          },
        }),
      );

      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'msg-1',
          'delta': 'Hello',
        }),
      );
      expect(_cellsByKind(state, TimelineCellKind.assistantMessage), isEmpty);

      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'msg-1',
          'delta': '\n',
        }),
      );
      final assistant = _cellsByKind(state, TimelineCellKind.assistantMessage);
      expect(assistant, hasLength(1));
      expect(assistant.first.markdownText, 'Hello');
      expect(assistant.first.isStreaming, isTrue);
    });

    test('first secondary freezes assistant interim into progress rows', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('codex/event/item_started', <String, dynamic>{
          'msg': <String, dynamic>{
            'type': 'item_started',
            'turn_id': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-1',
              'type': 'AgentMessage',
              'phase': 'commentary',
            },
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'msg-1',
          'delta': 'Thinking out loud\n',
        }),
      );
      expect(_cellsByKind(state, TimelineCellKind.progressText), hasLength(1));
      expect(_cellsByKind(state, TimelineCellKind.assistantMessage), isEmpty);

      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'cmd-1',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );

      final progress = _cellsByKind(state, TimelineCellKind.progressText);
      expect(progress, hasLength(1));
      expect(progress.first.markdownText, 'Thinking out loud');
    });

    test('assistant lines after secondary become progress rows in order', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'cmd-1',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('codex/event/item_started', <String, dynamic>{
          'msg': <String, dynamic>{
            'type': 'item_started',
            'turn_id': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-1',
              'type': 'AgentMessage',
              'phase': 'commentary',
            },
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'msg-1',
          'delta': 'line 1\nline 2\n',
        }),
      );
      state = reduceCommitTick(state);

      final progress = _cellsByKind(state, TimelineCellKind.progressText);
      expect(progress, hasLength(2));
      expect(progress[0].markdownText, 'line 1');
      expect(progress[1].markdownText, 'line 2');
    });

    test(
      'reasoning deltas update status header and finalize as summary cell',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('item/reasoning/textDelta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'reason-1',
            'delta': 'Checking options...',
          }),
        );

        expect(state.statusHeader, 'Thinking');
        expect(_cellsByKind(state, TimelineCellKind.reasoning), isEmpty);

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'reason-1',
              'type': 'reasoning',
              'status': 'completed',
            },
          }),
        );
        final reasoning = _cellsByKind(state, TimelineCellKind.reasoning);
        expect(reasoning, hasLength(1));
        expect(reasoning.first.markdownText, contains('Checking options'));
      },
    );

    test('thinking rows stay separated by reasoning item id', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'reason-1',
            'type': 'reasoning',
            'status': 'completed',
            'summary': <String>['first'],
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'reason-2',
            'type': 'reasoning',
            'status': 'completed',
            'summary': <String>['second'],
          },
        }),
      );

      final reasoning = _cellsByKind(state, TimelineCellKind.reasoning);
      expect(reasoning, hasLength(2));
      expect(reasoning[0].itemId, 'reason-1');
      expect(reasoning[1].itemId, 'reason-2');
    });

    test('turn diff updated updates status only and no persistent row', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('turn/diff/updated', <String, dynamic>{
          'turnId': 'turn-1',
          'diff': 'diff --git a b',
        }),
      );

      expect(state.statusHeader, 'Editing files');
      expect(
        _cellsByKind(
          state,
          TimelineCellKind.toolCall,
        ).where((cell) => (cell.title ?? '').contains('Editing files')),
        isEmpty,
      );
    });

    test('enteredReviewMode uses a user-friendly title', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'review-1',
            'type': 'enteredReviewMode',
            'status': 'completed',
          },
        }),
      );

      final reviewRows = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(reviewRows, hasLength(1));
      expect(reviewRows.single.title, 'Preparing review');
    });

    test('exitedReviewMode extracts review text outside worked', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'review-1',
            'type': 'exitedReviewMode',
            'status': 'completed',
            'review': 'Working tree is clean.',
          },
        }),
      );

      final reviewRows = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(reviewRows, hasLength(1));
      expect(reviewRows.single.title, 'Review finished');
      expect(reviewRows.single.detailsText, isNull);

      final reviewBodies = _cellsByKind(state, TimelineCellKind.progressText);
      expect(reviewBodies, hasLength(1));
      expect(reviewBodies.single.markdownText, 'Working tree is clean.');
      expect(
        reviewBodies.single.metadata[TimelineCellMetadata.uiPlacementKey],
        TimelineCellMetadata.outsideWorked,
      );
    });

    test('exitedReviewMode without review text does not create a body row', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'review-1',
            'type': 'exitedReviewMode',
            'status': 'completed',
          },
        }),
      );

      final reviewRows = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(reviewRows, hasLength(1));
      expect(reviewRows.single.title, 'Review finished');
      expect(reviewRows.single.detailsText, isNull);
      expect(_cellsByKind(state, TimelineCellKind.progressText), isEmpty);
    });

    test('token_count stores runtime metrics', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('codex/event/token_count', <String, dynamic>{
          'msg': <String, dynamic>{
            'info': <String, dynamic>{
              'total_token_usage': <String, dynamic>{'total_tokens': 123},
            },
          },
        }),
      );
      expect(state.turnRuntimeMetrics['totalTokens'], 123);
    });

    test('turn completion appends separator only when there is work', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'cmd-1',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'msg-1',
            'type': 'agentMessage',
            'status': 'completed',
            'text': 'done',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
            'durationMs': 120000,
          },
        }),
      );
      expect(_cellsByKind(state, TimelineCellKind.turnSeparator), hasLength(1));
    });

    test('turn completion with no work does not append separator', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'msg-1',
            'type': 'agentMessage',
            'status': 'completed',
            'text': 'done',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        }),
      );
      expect(_cellsByKind(state, TimelineCellKind.turnSeparator), isEmpty);
    });

    test(
      'assistant completion skips payload text when stream committed for same itemId',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-1',
                'type': 'AgentMessage',
                'phase': 'final_answer',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-1',
            'delta': 'stream line\n',
          }),
        );
        final before = _cellsByKind(state, TimelineCellKind.assistantMessage);
        expect(before, hasLength(1));
        expect(before.first.markdownText, 'stream line');

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-1',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'payload final that should be ignored',
            },
          }),
        );

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, 'stream line');
        expect(
          assistant.first.metadata['dedupeMode'],
          'stream_commit_same_item_id',
        );
      },
    );

    test(
      'assistant completion uses payload text when no stream committed for itemId',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-1',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'payload final',
            },
          }),
        );

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, 'payload final');
      },
    );

    test(
      'stream committed for one itemId does not block final payload for another itemId',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-stream',
                'type': 'AgentMessage',
                'phase': 'commentary',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-stream',
            'delta': 'stream only\n',
          }),
        );

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-final',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'final from payload',
            },
          }),
        );

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, 'final from payload');
        expect(assistant.first.itemId, 'msg-final');

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(progress, hasLength(1));
        expect(progress.first.itemId, 'msg-stream');
      },
    );

    test(
      'unknown phase agentMessage defaults to final and does not create empty assistant',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-unknown',
              'type': 'agentMessage',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-unknown',
            'delta': 'Hello mini\n',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-unknown',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'Hello mini',
            },
          }),
        );

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(assistant, hasLength(1));
        expect(assistant.first.itemId, 'msg-unknown');
        expect((assistant.first.markdownText ?? '').trim(), 'Hello mini');
        expect(progress, isEmpty);
      },
    );

    test(
      'explicit final item reclassifies prior unknown assistant stream to progress',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-unknown',
                'type': 'AgentMessage',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-unknown',
            'delta': 'Interim row\n',
          }),
        );
        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-final',
                'type': 'AgentMessage',
                'phase': 'final_answer',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-final',
            'delta': 'Final answer\n',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-final',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'Final answer',
            },
          }),
        );

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(assistant, hasLength(1));
        expect(assistant.first.itemId, 'msg-final');
        expect((assistant.first.markdownText ?? '').trim(), 'Final answer');
        expect(progress, hasLength(1));
        expect(progress.first.itemId, 'msg-unknown');
        expect((progress.first.markdownText ?? '').trim(), 'Interim row');
      },
    );

    test(
      'task_complete upserts existing empty assistant cell instead of duplicating',
      () {
        final now = DateTime.utc(2026, 2, 22);
        var state = SessionState(
          timelineCells: <TimelineCell>[
            TimelineCell(
              id: 'assistant-final-turn-1',
              turnId: 'turn-1',
              itemId: 'msg-missing',
              kind: TimelineCellKind.assistantMessage,
              status: TimelineCellStatus.completed,
              createdAt: now,
              updatedAt: now,
              markdownText: null,
            ),
          ],
        );

        state = reduceNotification(
          state,
          _event('codex/event/task_complete', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'task_complete',
              'turn_id': 'turn-1',
              'last_agent_message': 'Recovered final',
            },
          }),
        );

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.id, 'assistant-final-turn-1');
        expect(assistant.first.markdownText, 'Recovered final');
      },
    );

    test(
      'commandExecution classification uses commandActions then heuristic',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'cmd-1',
              'type': 'commandExecution',
              'command': 'echo hi',
              'status': 'inProgress',
              'commandActions': <String>['search'],
            },
          }),
        );
        final first = _cellsByKind(state, TimelineCellKind.toolCall).first;
        expect(first.title, 'Search');

        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'cmd-2',
              'type': 'commandExecution',
              'command': 'rg TODO .',
              'status': 'inProgress',
            },
          }),
        );
        final toolCells = _cellsByKind(state, TimelineCellKind.toolCall);
        expect(toolCells.last.title, 'Search');
      },
    );

    test('new secondary row starts collapsed on item started', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'cmd-1',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );

      final toolCells = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(toolCells, hasLength(1));
      expect(toolCells.first.isCollapsed, isTrue);
    });

    test('updates keep manual expanded state for existing secondary row', () {
      final now = DateTime.utc(2026, 2, 23);
      var state = SessionState(
        timelineCells: <TimelineCell>[
          TimelineCell(
            id: 'cmd-1',
            turnId: 'turn-1',
            itemId: 'cmd-1',
            kind: TimelineCellKind.toolCall,
            status: TimelineCellStatus.inProgress,
            createdAt: now,
            updatedAt: now,
            isCollapsed: false,
            title: 'Ran command',
            detailsText: 'old',
          ),
        ],
      );

      state = reduceNotification(
        state,
        _event('item/commandExecution/outputDelta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'cmd-1',
          'delta': ' + new output',
        }),
      );

      final toolCells = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(toolCells, hasLength(1));
      expect(toolCells.first.isCollapsed, isFalse);
      expect(toolCells.first.detailsText, contains('new output'));
    });

    test(
      'starting another secondary does not collapse an already open row',
      () {
        final now = DateTime.utc(2026, 2, 23);
        var state = SessionState(
          timelineCells: <TimelineCell>[
            TimelineCell(
              id: 'cmd-1',
              turnId: 'turn-1',
              itemId: 'cmd-1',
              kind: TimelineCellKind.toolCall,
              status: TimelineCellStatus.inProgress,
              createdAt: now,
              updatedAt: now,
              isCollapsed: false,
              title: 'Ran command',
              detailsText: 'open row',
            ),
          ],
        );

        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'cmd-2',
              'type': 'commandExecution',
              'command': 'pwd',
              'status': 'inProgress',
            },
          }),
        );

        final toolCells = _cellsByKind(state, TimelineCellKind.toolCall);
        expect(toolCells, hasLength(2));
        final first = toolCells.firstWhere((cell) => cell.id == 'cmd-1');
        final second = toolCells.firstWhere((cell) => cell.id == 'cmd-2');
        expect(first.isCollapsed, isFalse);
        expect(second.isCollapsed, isTrue);
      },
    );

    test(
      'commentary and final_answer in same turn do not duplicate content',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );

        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-commentary',
                'type': 'AgentMessage',
                'phase': 'commentary',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-commentary',
            'delta': 'Voy a revisar el README\n',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-commentary',
              'type': 'agentMessage',
              'text': 'Voy a revisar el README',
              'status': 'completed',
            },
          }),
        );

        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-final',
                'type': 'AgentMessage',
                'phase': 'final_answer',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-final',
            'delta': 'El readme.md está en español.\n',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-final',
              'type': 'agentMessage',
              'text': 'El readme.md está en español.',
              'status': 'completed',
            },
          }),
        );

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(progress, hasLength(1));
        expect(progress.first.markdownText, 'Voy a revisar el README');
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, 'El readme.md está en español.');
      },
    );

    test(
      'assistant stream is flushed at item boundary and not mixed across item ids',
      () {
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-a',
                'type': 'AgentMessage',
                'phase': 'commentary',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-a',
            'delta': 'line from a',
          }),
        );
        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-b',
                'type': 'AgentMessage',
                'phase': 'final_answer',
              },
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-b',
            'delta': 'line from b\n',
          }),
        );
        state = reduceCommitTick(state);

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(progress, hasLength(1));
        expect(progress.first.itemId, 'msg-a');
        expect(progress.first.markdownText, 'line from a');
        expect(assistant, hasLength(1));
        expect(assistant.first.itemId, 'msg-b');
        expect(assistant.first.markdownText, 'line from b');
      },
    );

    test('pending stream without newline is flushed on item/completed', () {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('codex/event/item_started', <String, dynamic>{
          'msg': <String, dynamic>{
            'type': 'item_started',
            'turn_id': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-final',
              'type': 'AgentMessage',
              'phase': 'final_answer',
            },
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'msg-final',
          'delta': 'partial without newline',
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'msg-final',
            'type': 'agentMessage',
            'text': 'partial without newline',
            'status': 'completed',
          },
        }),
      );

      final assistant = _cellsByKind(state, TimelineCellKind.assistantMessage);
      expect(assistant, hasLength(1));
      expect(assistant.first.markdownText, 'partial without newline');
    });

    test(
      'final_answer long text without newline streams in soft chunks before completion',
      () {
        final t0 = DateTime.utc(2026, 2, 22, 4, 0, 0);
        var state = const SessionState();
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
          now: t0,
        );
        state = reduceNotification(
          state,
          _event('codex/event/item_started', <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-final',
                'type': 'AgentMessage',
                'phase': 'final_answer',
              },
            },
          }),
          now: t0,
        );

        const finalText =
            'Este es un texto final bastante largo para probar streaming natural en chunks sin esperar siempre por salto de linea en una sola pieza.';
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-final',
            'delta': finalText,
          }),
          now: t0,
        );

        expect(_cellsByKind(state, TimelineCellKind.assistantMessage), isEmpty);

        state = reduceCommitTick(
          state,
          now: t0.add(const Duration(milliseconds: 220)),
        );
        final firstAssistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(firstAssistant, hasLength(1));
        final firstText = firstAssistant.first.markdownText ?? '';
        expect(firstText, isNotEmpty);
        expect(firstText.contains('\n'), isFalse);

        state = reduceCommitTick(
          state,
          now: t0.add(const Duration(milliseconds: 480)),
        );
        final secondAssistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(secondAssistant, hasLength(1));
        final secondText = secondAssistant.first.markdownText ?? '';
        expect(secondText.length, greaterThan(firstText.length));
        expect(secondText.contains('\n'), isFalse);

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-final',
              'type': 'agentMessage',
              'text': finalText,
              'status': 'completed',
            },
          }),
          now: t0.add(const Duration(seconds: 1)),
        );

        final completedAssistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(completedAssistant, hasLength(1));
        expect(completedAssistant.first.markdownText, finalText);
      },
    );

    test('commentary long text without newline does not soft-flush', () {
      final t0 = DateTime.utc(2026, 2, 22, 4, 0, 0);
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
        }),
        now: t0,
      );
      state = reduceNotification(
        state,
        _event('codex/event/item_started', <String, dynamic>{
          'msg': <String, dynamic>{
            'type': 'item_started',
            'turn_id': 'turn-1',
            'item': <String, dynamic>{
              'id': 'msg-commentary',
              'type': 'AgentMessage',
              'phase': 'commentary',
            },
          },
        }),
        now: t0,
      );

      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'msg-commentary',
          'delta':
              'Comentario largo sin salto de linea para validar que no haga soft flush dentro del worked.',
        }),
        now: t0,
      );

      state = reduceCommitTick(
        state,
        now: t0.add(const Duration(milliseconds: 500)),
      );

      expect(_cellsByKind(state, TimelineCellKind.assistantMessage), isEmpty);
      expect(_cellsByKind(state, TimelineCellKind.progressText), isEmpty);
    });

    test('unknown events only update raw log', () {
      final state = reduceNotification(
        const SessionState(),
        _event('unknown/event', <String, dynamic>{'x': 1}),
      );
      expect(state.activityLog, hasLength(1));
      expect(state.timelineCells, isEmpty);
    });

    test('interrupted turn with user stop inserts one system notice', () {
      var state = const SessionState(isInterrupting: true);
      state = reduceNotification(
        state,
        _event('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-stop',
            'threadId': 'thread-1',
            'status': 'interrupted',
          },
        }),
      );

      final notices = _cellsByKind(state, TimelineCellKind.systemNotice);
      expect(notices, hasLength(1));
      expect(notices.first.markdownText, 'Stopped by user');
      expect(notices.first.metadata['noticeType'], 'user_stop');
      expect(
        notices.first.metadata[TimelineCellMetadata.uiPlacementKey],
        TimelineCellMetadata.outsideWorked,
      );
      expect(notices.first.metadata['ephemeralInputOnly'], isTrue);
    });

    test('interrupted turn without user stop does not insert notice', () {
      var state = const SessionState(isInterrupting: false);
      state = reduceNotification(
        state,
        _event('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-stop',
            'threadId': 'thread-1',
            'status': 'interrupted',
          },
        }),
      );

      final notices = _cellsByKind(state, TimelineCellKind.systemNotice);
      expect(notices, isEmpty);
    });

    test(
      'user stop notice is not duplicated on repeated completion events',
      () {
        var state = const SessionState(isInterrupting: true);
        final event = _event('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-stop',
            'threadId': 'thread-1',
            'status': 'interrupted',
          },
        });
        state = reduceNotification(state, event);
        state = reduceNotification(state, event);

        final notices = _cellsByKind(state, TimelineCellKind.systemNotice);
        expect(notices, hasLength(1));
      },
    );
  });
}
