import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy task completion updates in place and closes only its turn', () {
    const original = <MobileCodexTimelineCell>[
      MobileCodexTimelineCell(
        id: 'progress-turn-legacy',
        kind: 'progressText',
        status: 'inProgress',
        turnId: 'turn-legacy',
        markdownText: 'Working',
        isStreaming: true,
      ),
      MobileCodexTimelineCell(
        id: 'assistant-turn-legacy',
        kind: 'assistantMessage',
        status: 'inProgress',
        turnId: 'turn-legacy',
        markdownText: 'Old answer',
        isStreaming: true,
        metadata: <String, Object?>{'source': 'legacy'},
      ),
      MobileCodexTimelineCell(
        id: 'other-turn',
        kind: 'reasoning',
        status: 'inProgress',
        turnId: 'turn-other',
        isStreaming: true,
      ),
    ];

    final cells = MobileCodexTimelineReducer.reduce(original, <String, Object?>{
      'method': 'codex/event/task_complete',
      'params': <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-legacy',
          'last_agent_message': 'Final answer',
        },
      },
    });

    expect(cells.map((cell) => cell.id), <String>[
      'progress-turn-legacy',
      'assistant-turn-legacy',
      'other-turn',
    ]);
    expect(cells[0].status, 'completed');
    expect(cells[0].isStreaming, isFalse);
    expect(cells[1].markdownText, 'Final answer');
    expect(cells[1].status, 'completed');
    expect(cells[1].isStreaming, isFalse);
    expect(cells[1].metadata['source'], 'legacy');
    expect(cells[2], same(original[2]));
  });

  test('legacy item aliases merge and malformed item payloads are ignored', () {
    var cells = MobileCodexTimelineReducer.reduce(
      const <MobileCodexTimelineCell>[],
      <String, Object?>{
        'method': 'codex/event/item_started',
        'params': <String, Object?>{
          'msg': <String, Object?>{
            'turn_id': 'turn-legacy',
            'item': <String, Object?>{
              'id': 'command-1',
              'type': 'commandExecution',
              'command': 'pwd',
            },
          },
        },
      },
    );
    cells = MobileCodexTimelineReducer.reduce(cells, <String, Object?>{
      'method': 'codex/event/item_completed',
      'params': <String, Object?>{
        'msg': <String, Object?>{
          'turn_id': 'turn-legacy',
          'item': <String, Object?>{
            'id': 'command-1',
            'type': 'commandExecution',
            'command': 'pwd',
            'aggregatedOutput': '/workspace',
          },
        },
      },
    });

    expect(cells, hasLength(1));
    expect(cells.single.id, 'item-command-1');
    expect(cells.single.itemId, 'command-1');
    expect(cells.single.kind, 'command');
    expect(cells.single.status, 'completed');
    expect(cells.single.detailsText, '/workspace');
    expect(cells.single.isStreaming, isFalse);

    final malformed = MobileCodexTimelineReducer.reduce(
      cells,
      <String, Object?>{
        'method': 'item/completed',
        'params': <Object?>['not', 'a', 'map'],
      },
    );
    expect(malformed, same(cells));
  });
}
