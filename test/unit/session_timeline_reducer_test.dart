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
    test('assistant streams into a single cell', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
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

      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-1',
          'itemId': 'msg-1',
          'delta': ' world',
        }),
      );

      final assistant = _cellsByKind(state, TimelineCellKind.assistantMessage);
      expect(assistant, hasLength(1));
      expect(assistant.first.markdownText, 'Hello world');
      expect(assistant.first.isStreaming, isTrue);
      expect(state.activeStreamingAssistantCellId, assistant.first.id);
    });

    test('assistant completed merges final text without duplication', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-2', 'threadId': 'thread-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-2',
          'itemId': 'msg-2',
          'delta': 'Hola',
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-2',
          'item': <String, dynamic>{
            'id': 'msg-2',
            'type': 'agentMessage',
            'status': 'completed',
            'text': 'Hola, en que te ayudo?',
          },
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-2',
          'item': <String, dynamic>{
            'id': 'msg-2',
            'type': 'agentMessage',
            'status': 'completed',
            'text': 'Hola, en que te ayudo?',
          },
        }),
      );

      final assistant = _cellsByKind(state, TimelineCellKind.assistantMessage);
      expect(assistant, hasLength(1));
      expect(assistant.first.markdownText, 'Hola, en que te ayudo?');
      expect(assistant.first.isStreaming, isFalse);
    });

    test('creates assistant from item completed when no deltas arrived', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-fallback',
            'threadId': 'thread-1',
          },
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-fallback',
          'item': <String, dynamic>{
            'id': 'msg-fallback',
            'type': 'agentMessage',
            'status': 'completed',
            'text': 'Final answer without stream',
          },
        }),
      );

      final assistant = _cellsByKind(state, TimelineCellKind.assistantMessage);
      expect(assistant, hasLength(1));
      expect(assistant.first.id, 'msg-fallback');
      expect(assistant.first.markdownText, 'Final answer without stream');
      expect(assistant.first.isStreaming, isFalse);
    });

    test('builds tool cell from started, output delta and completed', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-3', 'threadId': 'thread-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-3',
          'item': <String, dynamic>{
            'id': 'cmd-1',
            'type': 'commandExecution',
            'command': 'git status',
            'cwd': '/repo',
            'status': 'inProgress',
          },
        }),
      );

      state = reduceNotification(
        state,
        _event('item/commandExecution/outputDelta', <String, dynamic>{
          'turnId': 'turn-3',
          'itemId': 'cmd-1',
          'delta': 'On branch main\n',
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-3',
          'item': <String, dynamic>{
            'id': 'cmd-1',
            'type': 'commandExecution',
            'command': 'git status',
            'cwd': '/repo',
            'status': 'completed',
            'aggregatedOutput': 'On branch main\n',
          },
        }),
      );

      final tools = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(tools, hasLength(1));
      expect(tools.first.title, 'Ran git status');
      expect(tools.first.detailsText, contains('On branch main'));
      expect(tools.first.status, TimelineCellStatus.completed);
    });

    test('reasoning delta and completed stay inline in same cell', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-4', 'threadId': 'thread-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/reasoning/summaryTextDelta', <String, dynamic>{
          'turnId': 'turn-4',
          'itemId': 'reason-1',
          'delta': 'Thinking step 1. ',
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-4',
          'item': <String, dynamic>{
            'id': 'reason-1',
            'type': 'reasoning',
            'status': 'completed',
            'summary': 'Thinking step 1. Final thought.',
          },
        }),
      );

      final reasoning = _cellsByKind(state, TimelineCellKind.reasoning);
      expect(reasoning, hasLength(1));
      expect(reasoning.first.markdownText, contains('Final thought'));
      expect(reasoning.first.status, TimelineCellStatus.completed);
    });

    test(
      'new secondary item auto-collapses previous secondary during streaming',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-4b', 'threadId': 'thread-1'},
          }),
        );

        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-4b',
            'item': <String, dynamic>{
              'id': 'cmd-4b',
              'type': 'commandExecution',
              'command': 'ls',
              'status': 'inProgress',
            },
          }),
        );

        state = reduceNotification(
          state,
          _event('item/reasoning/summaryTextDelta', <String, dynamic>{
            'turnId': 'turn-4b',
            'itemId': 'reason-4b',
            'delta': 'thinking',
          }),
        );

        final tools = _cellsByKind(state, TimelineCellKind.toolCall);
        final reasoning = _cellsByKind(state, TimelineCellKind.reasoning);
        expect(tools, hasLength(1));
        expect(reasoning, hasLength(1));
        expect(tools.first.isCollapsed, isTrue);
        expect(reasoning.first.isCollapsed, isFalse);
      },
    );

    test('secondary deltas on same item keep that item expanded', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-4c', 'threadId': 'thread-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-4c',
          'item': <String, dynamic>{
            'id': 'cmd-4c',
            'type': 'commandExecution',
            'command': 'cat README.md',
            'status': 'inProgress',
          },
        }),
      );

      state = reduceNotification(
        state,
        _event('item/commandExecution/outputDelta', <String, dynamic>{
          'turnId': 'turn-4c',
          'itemId': 'cmd-4c',
          'delta': 'line 1\n',
        }),
      );

      final tools = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(tools, hasLength(1));
      expect(tools.first.id, 'cmd-4c');
      expect(tools.first.isCollapsed, isFalse);
    });

    test('keeps chronological order and links optimistic user to turn', () {
      var state = const SessionState();

      state = appendOptimisticUserMessage(state, text: 'implement feature x');
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-5', 'threadId': 'thread-1'},
        }),
      );
      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-5',
          'item': <String, dynamic>{
            'id': 'cmd-2',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-5',
          'itemId': 'msg-5',
          'delta': 'done',
        }),
      );

      expect(state.timelineCells, hasLength(3));
      expect(state.timelineCells[0].kind, TimelineCellKind.userMessage);
      expect(state.timelineCells[0].turnId, 'turn-5');
      expect(state.timelineCells[1].kind, TimelineCellKind.toolCall);
      expect(state.timelineCells[2].kind, TimelineCellKind.assistantMessage);
    });

    test(
      'turn completed auto-collapses secondary cells and appends separator',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-6', 'threadId': 'thread-1'},
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-6',
            'item': <String, dynamic>{
              'id': 'cmd-6',
              'type': 'commandExecution',
              'command': 'pwd',
              'status': 'inProgress',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/reasoning/summaryTextDelta', <String, dynamic>{
            'turnId': 'turn-6',
            'itemId': 'reason-6',
            'delta': 'thinking',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-6',
            'itemId': 'msg-6',
            'delta': 'answer',
          }),
        );

        state = reduceNotification(
          state,
          _event('turn/completed', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-6',
              'threadId': 'thread-1',
              'status': 'completed',
              'durationMs': 1200,
              'usage': <String, dynamic>{'totalTokens': 321},
            },
          }),
        );

        final tools = _cellsByKind(state, TimelineCellKind.toolCall);
        final reasoning = _cellsByKind(state, TimelineCellKind.reasoning);
        final separators = _cellsByKind(state, TimelineCellKind.turnSeparator);
        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );

        expect(tools, hasLength(1));
        expect(tools.first.isCollapsed, isTrue);
        expect(reasoning, hasLength(1));
        expect(reasoning.first.isCollapsed, isTrue);
        expect(assistant, hasLength(1));
        expect(assistant.first.isStreaming, isFalse);
        expect(separators, hasLength(1));
        expect(separators.first.title, 'turn completed');
        expect(separators.first.subtitle, contains('tokens'));
        expect(state.activeTurnId, isNull);
        expect(state.activeStreamingAssistantCellId, isNull);
      },
    );

    test('unknown events only affect raw log', () {
      final state = reduceNotification(
        const SessionState(),
        _event('foo/bar', <String, dynamic>{'x': 1}),
      );

      expect(state.timelineCells, isEmpty);
      expect(state.activityLog, hasLength(1));
      expect(state.activityLog.first, startsWith('foo/bar:'));
    });
  });
}
