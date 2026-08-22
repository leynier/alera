import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _event(String method, Map<String, Object?> params) =>
    <String, Object?>{'method': method, 'params': params};

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);

  test('reduces current plan and patch notifications', () {
    var cells = CodexTimelineReducer.reduce(
      const <CodexTimelineCell>[],
      _event('turn/plan/updated', <String, Object?>{
        'turnId': 'turn-1',
        'explanation': 'Approach',
        'plan': <Object?>[
          <String, Object?>{'step': 'Inspect', 'status': 'completed'},
          <String, Object?>{'step': 'Implement', 'status': 'inProgress'},
        ],
      }),
      now: now,
    );
    expect(cells.single.kind, CodexTimelineKind.plan);
    expect(cells.single.markdownText, contains('- [x] Inspect'));
    expect(cells.single.markdownText, contains('*(In progress)*'));

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('item/fileChange/patchUpdated', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'files-1',
        'changes': <Object?>[
          <String, Object?>{'path': 'README.md', 'kind': 'update'},
        ],
      }),
      now: now,
    );
    final patch = cells.singleWhere((cell) => cell.itemId == 'files-1');
    expect(patch.kind, CodexTimelineKind.diff);
    expect(patch.metadata['changes'], isNotEmpty);
  });

  test('surfaces compaction, reroutes and warnings', () {
    var cells = <CodexTimelineCell>[];
    for (final event in <Map<String, Object?>>[
      _event('thread/compacted', <String, Object?>{'turnId': 'turn-1'}),
      _event('model/rerouted', <String, Object?>{
        'turnId': 'turn-1',
        'fromModel': 'gpt-a',
        'toModel': 'gpt-b',
        'reason': 'capacity',
      }),
      _event('guardianWarning', <String, Object?>{
        'turnId': 'turn-1',
        'message': 'Review this action.',
        'details': 'The operation needs explicit confirmation.',
      }),
    ]) {
      cells = CodexTimelineReducer.reduce(cells, event, now: now);
    }
    expect(cells[0].title, 'Compacted');
    expect(cells[1].markdownText, contains('gpt-b'));
    expect(cells[2].title, 'Safety warning');
    expect(cells[2].markdownText, contains('explicit confirmation'));
  });

  test('tracks context compaction once across canonical and legacy events', () {
    var cells = CodexTimelineReducer.reduce(
      const <CodexTimelineCell>[],
      _event('item/started', <String, Object?>{
        'turnId': 'turn-1',
        'item': <String, Object?>{
          'id': 'compact-1',
          'type': 'contextCompaction',
          'title': 'Context automatically compacting',
        },
      }),
      now: now,
    );
    expect(cells.single.title, 'Compacting');
    expect(cells.single.status, CodexTimelineStatus.inProgress);
    expect(cells.single.isStreaming, isTrue);

    cells = CodexTimelineReducer.reduce(
      cells,
      _event('item/completed', <String, Object?>{
        'turnId': 'turn-1',
        'item': <String, Object?>{
          'id': 'compact-1',
          'type': 'contextCompaction',
        },
      }),
      now: now.add(const Duration(seconds: 1)),
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _event('thread/compacted', <String, Object?>{'turnId': 'turn-1'}),
      now: now.add(const Duration(seconds: 2)),
    );
    expect(cells, hasLength(1));
    expect(cells.single.id, 'item-compact-1');
    expect(cells.single.title, 'Compacted');
    expect(cells.single.status, CodexTimelineStatus.completed);
    expect(cells.single.isStreaming, isFalse);
  });

  test('surfaces verification, safety buffering and MCP startup', () {
    var cells = <CodexTimelineCell>[];
    for (final event in <Map<String, Object?>>[
      _event('model/verification', <String, Object?>{
        'turnId': 'turn-1',
        'verifications': <String>['trustedAccessForCyber'],
      }),
      _event('model/safetyBuffering/updated', <String, Object?>{
        'turnId': 'turn-1',
        'showBufferingUi': true,
        'fasterModel': 'gpt-fast',
      }),
      _event('model/safetyBuffering/updated', <String, Object?>{
        'turnId': 'turn-1',
        'showBufferingUi': false,
      }),
      _event('mcpServer/startupStatus/updated', <String, Object?>{
        'threadId': 'thread-1',
        'name': 'filesystem',
        'status': 'failed',
        'error': 'Authentication required',
      }),
    ]) {
      cells = CodexTimelineReducer.reduce(cells, event, now: now);
    }
    expect(cells, hasLength(3));
    expect(cells[0].title, 'Account verification');
    expect(cells[1].status, CodexTimelineStatus.completed);
    expect(cells[2].status, CodexTimelineStatus.failed);
    expect(cells[2].detailsText, 'Authentication required');
  });
}
