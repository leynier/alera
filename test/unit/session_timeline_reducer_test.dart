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

    test(
      'freeze assistant interim text into progressText on first secondary',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-progress-freeze',
              'threadId': 'thread-1',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-progress-freeze',
            'itemId': 'msg-progress-freeze',
            'delta': 'Thinking out loud',
          }),
        );

        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-progress-freeze',
            'item': <String, dynamic>{
              'id': 'cmd-progress-freeze',
              'type': 'commandExecution',
              'command': 'rg TODO',
              'status': 'inProgress',
            },
          }),
        );

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(progress, hasLength(1));
        expect(progress.first.markdownText, 'Thinking out loud');
        expect(progress.first.metadata['isInterim'], isTrue);

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, isNull);
      },
    );

    test(
      'assistant deltas after secondary starts append to active progressText',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-progress-live',
              'threadId': 'thread-1',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-progress-live',
            'item': <String, dynamic>{
              'id': 'cmd-progress-live',
              'type': 'commandExecution',
              'command': 'ls',
              'status': 'inProgress',
            },
          }),
        );

        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-progress-live',
            'itemId': 'msg-progress-live',
            'delta': 'line 1',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-progress-live',
            'itemId': 'msg-progress-live',
            'delta': '\nline 2',
          }),
        );

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(progress, hasLength(1));
        expect(progress.first.markdownText, 'line 1\nline 2');
        expect(progress.first.status, TimelineCellStatus.inProgress);

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, isEmpty);
      },
    );

    test(
      'new secondary phase freezes current progressText and next deltas create a new one',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-progress-phase',
              'threadId': 'thread-1',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-progress-phase',
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
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-progress-phase',
            'itemId': 'msg-progress-phase',
            'delta': 'phase one',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-progress-phase',
            'item': <String, dynamic>{
              'id': 'reason-1',
              'type': 'reasoning',
              'status': 'inProgress',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-progress-phase',
            'itemId': 'msg-progress-phase',
            'delta': 'phase two',
          }),
        );

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(progress, hasLength(2));
        expect(progress[0].markdownText, 'phase one');
        expect(progress[0].status, TimelineCellStatus.completed);
        expect(progress[0].metadata['phaseClosedAtTurnItemId'], 'reason-1');
        expect(progress[1].markdownText, 'phase two');
      },
    );

    test('progressText metadata includes interim source marker', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-source',
            'threadId': 'thread-1',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-source',
          'item': <String, dynamic>{
            'id': 'cmd-source',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-source',
          'itemId': 'msg-source',
          'delta': 'working',
        }),
      );

      final progress = _cellsByKind(state, TimelineCellKind.progressText);
      expect(progress, hasLength(1));
      expect(progress.first.metadata['isInterim'], isTrue);
      expect(progress.first.metadata['source'], 'assistant_delta');
    });

    test('filters internal-like interim lines from progressText', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-filter',
            'threadId': 'thread-1',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-filter',
          'item': <String, dynamic>{
            'id': 'cmd-filter',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-filter',
          'itemId': 'msg-filter',
          'delta': 'Finalizing response with file path',
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-filter',
          'itemId': 'msg-filter',
          'delta': 'Voy a validar el archivo ahora.',
        }),
      );

      final progress = _cellsByKind(state, TimelineCellKind.progressText);
      expect(progress, hasLength(1));
      expect(progress.first.markdownText, 'Voy a validar el archivo ahora.');
      expect(
        progress.first.markdownText,
        isNot(contains('Finalizing response')),
      );
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

    test(
      'assistant completion keeps progressText rows and sets final message',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-final-preserve',
              'threadId': 'thread-1',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-final-preserve',
            'item': <String, dynamic>{
              'id': 'cmd-final-preserve',
              'type': 'commandExecution',
              'command': 'ls',
              'status': 'inProgress',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-final-preserve',
            'itemId': 'msg-final-preserve',
            'delta': 'interim',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-final-preserve',
            'item': <String, dynamic>{
              'id': 'msg-final-preserve',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'final answer',
            },
          }),
        );

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(progress, hasLength(1));
        expect(progress.first.markdownText, 'interim');

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, 'final answer');
      },
    );

    test(
      'assistant completion dedupes when final text exactly matches interim text',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-dedupe-exact',
              'threadId': 'thread-1',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-dedupe-exact',
            'item': <String, dynamic>{
              'id': 'cmd-dedupe-exact',
              'type': 'commandExecution',
              'command': 'ls',
              'status': 'inProgress',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-dedupe-exact',
            'itemId': 'msg-dedupe-exact',
            'delta': 'Mismo texto',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-dedupe-exact',
            'item': <String, dynamic>{
              'id': 'msg-dedupe-exact',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'Mismo texto',
            },
          }),
        );

        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        expect(progress, hasLength(1));
        expect((progress.first.markdownText ?? '').trim(), isEmpty);

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, 'Mismo texto');
        expect(
          assistant.first.metadata['dedupeMode'],
          'exact_match_trim_interim',
        );
      },
    );

    test(
      'assistant completion trims duplicated final prefix overlap conservatively',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-dedupe-overlap',
              'threadId': 'thread-1',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-dedupe-overlap',
            'item': <String, dynamic>{
              'id': 'cmd-dedupe-overlap',
              'type': 'commandExecution',
              'command': 'ls',
              'status': 'inProgress',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-dedupe-overlap',
            'itemId': 'msg-dedupe-overlap',
            'delta': 'Trabajando sobre README y validando',
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-dedupe-overlap',
            'item': <String, dynamic>{
              'id': 'msg-dedupe-overlap',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'y validando cambios finales',
            },
          }),
        );

        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );
        expect(assistant, hasLength(1));
        expect(assistant.first.markdownText, 'cambios finales');
        expect(
          assistant.first.metadata['dedupeMode'],
          'interim_ends_with_final_prefix_trim_final_prefix',
        );
      },
    );

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

    test('commandExecution uses commandActions for human-friendly labels', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-actions', 'threadId': 'thr-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-actions',
          'item': <String, dynamic>{
            'id': 'cmd-read',
            'type': 'commandExecution',
            'command': 'cat README.md',
            'commandActions': <String>['read'],
            'status': 'completed',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-actions',
          'item': <String, dynamic>{
            'id': 'cmd-search',
            'type': 'commandExecution',
            'command': 'rg timeline',
            'commandActions': <String>['search'],
            'status': 'completed',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-actions',
          'item': <String, dynamic>{
            'id': 'cmd-unknown',
            'type': 'commandExecution',
            'command': 'git status',
            'commandActions': <String>['unknown'],
            'status': 'completed',
          },
        }),
      );

      final tools = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(tools, hasLength(3));

      expect(tools[0].title, 'Read');
      expect(tools[0].subtitle, 'cat README.md');
      expect(tools[0].metadata['isExploratory'], isTrue);
      expect(tools[0].metadata['exploreBucket'], 'file');
      expect(tools[0].metadata['commandActionsNormalized'], <String>['read']);

      expect(tools[1].title, 'Search');
      expect(tools[1].subtitle, 'rg timeline');
      expect(tools[1].metadata['isExploratory'], isTrue);
      expect(tools[1].metadata['exploreBucket'], 'search');

      expect(tools[2].title, 'Ran git status');
      expect(tools[2].metadata['isExploratory'], isFalse);
    });

    test(
      'commandExecution falls back to heuristics when actions are missing',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-heuristic',
              'threadId': 'thr-1',
            },
          }),
        );

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-heuristic',
            'item': <String, dynamic>{
              'id': 'cmd-list',
              'type': 'commandExecution',
              'command': 'rg --files lib',
              'status': 'completed',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-heuristic',
            'item': <String, dynamic>{
              'id': 'cmd-search',
              'type': 'commandExecution',
              'command': 'grep TODO README.md',
              'status': 'completed',
            },
          }),
        );
        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-heuristic',
            'item': <String, dynamic>{
              'id': 'cmd-ran',
              'type': 'commandExecution',
              'command': 'git status',
              'status': 'completed',
            },
          }),
        );

        final tools = _cellsByKind(state, TimelineCellKind.toolCall);
        expect(tools, hasLength(3));
        expect(tools[0].title, 'List');
        expect(tools[0].metadata['exploreBucket'], 'file');
        expect(tools[1].title, 'Search');
        expect(tools[1].metadata['exploreBucket'], 'search');
        expect(tools[2].title, 'Ran git status');
        expect(tools[2].metadata['isExploratory'], isFalse);
      },
    );

    test('integrated items get human-friendly labels', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-integrated',
            'threadId': 'thr-1',
          },
        }),
      );

      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-integrated',
          'item': <String, dynamic>{
            'id': 'change-1',
            'type': 'fileChange',
            'status': 'completed',
            'changes': <Map<String, dynamic>>[
              <String, dynamic>{'path': 'lib/a.dart'},
              <String, dynamic>{'path': 'lib/b.dart'},
            ],
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-integrated',
          'item': <String, dynamic>{
            'id': 'search-1',
            'type': 'webSearch',
            'status': 'completed',
            'action': 'search',
            'query': 'codex app-server',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-integrated',
          'item': <String, dynamic>{
            'id': 'mcp-1',
            'type': 'mcpToolCall',
            'status': 'completed',
            'server': 'filesystem',
            'tool': 'read_file',
          },
        }),
      );

      final tools = _cellsByKind(state, TimelineCellKind.toolCall);
      expect(tools, hasLength(3));
      expect(tools[0].title, 'Edited 2 files');
      expect(tools[1].title, 'Web search: Search');
      expect(tools[1].subtitle, 'codex app-server');
      expect(tools[2].title, 'MCP: filesystem/read_file');
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
      expect(state.timelineCells[2].kind, TimelineCellKind.progressText);
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
        final progress = _cellsByKind(state, TimelineCellKind.progressText);
        final separators = _cellsByKind(state, TimelineCellKind.turnSeparator);
        final assistant = _cellsByKind(
          state,
          TimelineCellKind.assistantMessage,
        );

        expect(tools, hasLength(1));
        expect(tools.first.isCollapsed, isTrue);
        expect(reasoning, hasLength(1));
        expect(reasoning.first.isCollapsed, isTrue);
        expect(progress, hasLength(1));
        expect(progress.first.markdownText, 'answer');
        expect(progress.first.status, TimelineCellStatus.completed);
        expect(assistant, isEmpty);
        expect(separators, hasLength(1));
        expect(separators.first.title, 'turn completed');
        expect(separators.first.subtitle, contains('tokens'));
        expect(state.activeTurnId, isNull);
        expect(state.activeStreamingAssistantCellId, isNull);
      },
    );

    test(
      'turn completed computes duration from timeline when payload has none',
      () {
        final t0 = DateTime.utc(2026, 2, 22, 10, 0, 0);
        var state = const SessionState();

        state = appendOptimisticUserMessage(state, text: 'hello', now: t0);
        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-duration',
              'threadId': 'thread-1',
            },
          }),
          now: t0,
        );
        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-duration',
            'item': <String, dynamic>{
              'id': 'cmd-duration',
              'type': 'commandExecution',
              'command': 'ls',
              'status': 'inProgress',
            },
          }),
          now: t0.add(const Duration(seconds: 5)),
        );
        state = reduceNotification(
          state,
          _event('turn/completed', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-duration',
              'threadId': 'thread-1',
              'status': 'completed',
            },
          }),
          now: t0.add(const Duration(seconds: 80)),
        );

        final separators = _cellsByKind(state, TimelineCellKind.turnSeparator);
        expect(separators, hasLength(1));
        expect(separators.first.subtitle, startsWith('1m 20s'));
        expect(separators.first.metadata['computedDurationMs'], isNotNull);
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
