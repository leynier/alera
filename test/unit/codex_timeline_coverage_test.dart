import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _event(String method, Map<String, Object?> params) =>
    <String, Object?>{'method': method, 'params': params};

CodexTimelineCell _cell({
  required String id,
  required String turnId,
  CodexTimelineKind kind = CodexTimelineKind.progressText,
  CodexTimelineStatus status = CodexTimelineStatus.inProgress,
  bool streaming = true,
}) => CodexTimelineCell(
  id: id,
  turnId: turnId,
  kind: kind,
  status: status,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isStreaming: streaming,
);

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);

  test(
    'reducer closes legacy and failed turns without touching other rows',
    () {
      var cells = CodexTimelineReducer.reduce(
        <CodexTimelineCell>[],
        _event('item/agentMessage/delta', <String, Object?>{
          'turnId': 'turn-1',
          'delta': 'partial',
        }),
        now: now,
      );
      cells = <CodexTimelineCell>[
        ...cells,
        _cell(id: 'other', turnId: 'turn-2'),
      ];
      cells = CodexTimelineReducer.reduce(
        cells,
        _event('codex/event/task_complete', <String, Object?>{
          'msg': <String, Object?>{
            'turn_id': 'turn-1',
            'lastAgentMessage': 'complete',
          },
        }),
        now: now,
      );
      expect(cells.first.markdownText, 'complete');
      expect(cells.first.isStreaming, isFalse);
      expect(cells.last.isStreaming, isTrue);

      final stringFailure = CodexTimelineReducer.reduce(
        <CodexTimelineCell>[
          _cell(id: 'one', turnId: 'turn-1'),
          _cell(id: 'other-turn', turnId: 'turn-2'),
        ],
        _event('turn/completed', <String, Object?>{
          'turn': <String, Object?>{'id': 'turn-1', 'error': 'failed'},
        }),
        now: now,
      );
      expect(stringFailure.first.status, CodexTimelineStatus.failed);
      expect(stringFailure.last.isStreaming, isTrue);

      final mapFailure = CodexTimelineReducer.reduce(
        <CodexTimelineCell>[_cell(id: 'one', turnId: 'turn-1')],
        _event('turn/completed', <String, Object?>{
          'turn': <String, Object?>{
            'id': 'turn-1',
            'error': <String, Object?>{'message': 'failed'},
          },
        }),
        now: now,
      );
      expect(mapFailure.single.status, CodexTimelineStatus.failed);
    },
  );

  test('reducer handles snapshot, reasoning and anonymous output deltas', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _event('turn/diff/updated', <String, Object?>{
        'turnId': 'turn-1',
        'delta': 'delta diff',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _event('turn/diff/updated', <String, Object?>{
        'turnId': 'turn-2',
        'text': 'text diff',
      }),
      now: now,
    );
    final unchanged = CodexTimelineReducer.reduce(
      cells,
      _event('turn/diff/updated', <String, Object?>{
        'turnId': 'turn-2',
        'text': 'text diff',
      }),
      now: now,
    );
    expect(unchanged, same(cells));

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('item/reasoning/summaryTextDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'reason',
        'text': 'thinking',
      }),
      now: now,
    );
    final repeatedReasoning = CodexTimelineReducer.reduce(
      cells,
      _event('item/reasoning/summaryTextDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'reason',
        'text': 'thinking',
      }),
      now: now,
    );
    expect(repeatedReasoning, same(cells));
    cells = CodexTimelineReducer.reduce(
      cells,
      _event('item/reasoning/summaryTextDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'reason',
        'text': ' more',
      }),
      now: now,
    );

    for (final entry in <(String, String)>[
      ('item/commandExecution/outputDelta', 'command'),
      ('item/mcpToolCall/outputDelta', 'tool'),
      ('item/plan/delta', 'plan'),
    ]) {
      cells = CodexTimelineReducer.reduce(
        cells,
        _event(entry.$1, <String, Object?>{
          'turnId': 'turn-${entry.$2}',
          'output': entry.$2,
        }),
        now: now,
      );
    }
    expect(cells.any((cell) => cell.kind == CodexTimelineKind.command), isTrue);
    expect(
      cells.any((cell) => cell.kind == CodexTimelineKind.toolCall),
      isTrue,
    );
    expect(cells.any((cell) => cell.kind == CodexTimelineKind.plan), isTrue);
  });

  test('reducer coalesces subagent progress and completion', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _event('item/subagent/progress', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'agent-1',
        'summary': 'working',
      }),
      now: now,
    );
    final repeated = CodexTimelineReducer.reduce(
      cells,
      _event('item/subagent/progress', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'agent-1',
        'summary': 'working',
      }),
      now: now,
    );
    expect(repeated, same(cells));

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('item/subagent/completed', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'agent-1',
      }),
      now: now,
    );
    expect(cells.single.markdownText, 'working');

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('item/subagent/completed', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'agent-1',
        'message': ' done',
      }),
      now: now,
    );
    expect(cells.single.markdownText, 'working done');
    expect(cells.single.status, CodexTimelineStatus.completed);
    expect(cells.single.isStreaming, isFalse);

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('item/collab/end', <String, Object?>{
        'turnId': 'turn-2',
        'itemId': 'agent-2',
      }),
      now: now,
    );
    expect(cells.last.kind, CodexTimelineKind.subAgent);
    expect(cells.last.isStreaming, isFalse);
  });

  test('reducer maps item status, fallback kinds, errors and reviews', () {
    var cells = <CodexTimelineCell>[];
    for (final item in <Map<String, Object?>>[
      <String, Object?>{'type': 'user_message', 'text': 'question'},
      <String, Object?>{
        'type': 'assistant',
        'phase': 'commentary',
        'text': 'progress',
        'status': 'failed',
      },
      <String, Object?>{
        'type': 'reasoning',
        'summary': 'reason',
        'status': 'declined',
      },
      <String, Object?>{'type': 'fileChange', 'diff': 'diff'},
      <String, Object?>{'type': 'commandExecution', 'command': 'pwd'},
      <String, Object?>{'type': 'collab', 'message': 'delegated'},
      <String, Object?>{'type': 'plan', 'text': 'plan'},
      <String, Object?>{'type': 'tool', 'name': 'Tool', 'result': 'done'},
      <String, Object?>{'type': 'unknown', 'title': 'Activity'},
    ]) {
      cells = CodexTimelineReducer.reduce(
        cells,
        _event('item/completed', <String, Object?>{
          'turnId': 'turn-${item['type']}',
          'item': item,
        }),
        now: now,
      );
    }
    expect(
      cells.any((cell) => cell.kind == CodexTimelineKind.userMessage),
      isTrue,
    );
    expect(
      cells.any((cell) => cell.status == CodexTimelineStatus.failed),
      isTrue,
    );
    expect(
      cells.any((cell) => cell.status == CodexTimelineStatus.declined),
      isTrue,
    );
    expect(cells.any((cell) => cell.title == 'Activity'), isTrue);

    final noError = CodexTimelineReducer.reduce(
      cells,
      _event('stream/error', const <String, Object?>{}),
      now: now,
    );
    expect(noError, same(cells));
    cells = CodexTimelineReducer.reduce(
      cells,
      _event('stream_error', <String, Object?>{'error': 'broken'}),
      now: now,
    );
    expect(cells.last.status, CodexTimelineStatus.failed);

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('review/enter', <String, Object?>{
        'turnId': 'turn-review',
        'itemId': 'review-1',
        'review': 'Review body',
      }),
      now: now,
    );
    expect(cells.last.markdownText, 'Review body');
    expect(
      cells.last.metadata[CodexTimelineMetadata.uiPlacement],
      CodexTimelineMetadata.outsideWorked,
    );

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('review/exit', <String, Object?>{'turnId': 'turn-review-2'}),
      now: now,
    );
    expect(cells.last.title, 'Review finished');
  });

  test(
    'timeline cells preserve defaults, typed metadata and collapse state',
    () {
      final parsed = CodexTimelineCell.fromJson(<String, Object?>{
        'id': 'item-cell',
        'kind': 'unknown',
        'status': 'unknown',
        'metadata': <Object?, Object?>{1: 'one'},
      });
      expect(parsed.kind, CodexTimelineKind.systemNotice);
      expect(parsed.status, CodexTimelineStatus.info);
      expect(parsed.metadata, <String, Object?>{'1': 'one'});

      final collapsed = parsed.copyWith(isCollapsed: true);
      final reduced = CodexTimelineReducer.reduce(
        <CodexTimelineCell>[collapsed],
        _event('item/updated', <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'cell',
            'type': 'tool',
            'output': 'done',
          },
        }),
        now: now,
      );
      expect(reduced.single.isCollapsed, isTrue);
      expect(reduced.single.toJson()['metadata'], contains('1'));

      final nonStringParams = CodexTimelineReducer.reduce(
        const <CodexTimelineCell>[],
        <String, Object?>{
          'method': 'turn/started',
          'params': <Object?, Object?>{1: 'ignored', 'turnId': 'turn-map'},
        },
        now: now,
      );
      expect(nonStringParams.single.turnId, 'turn-map');
    },
  );
}
