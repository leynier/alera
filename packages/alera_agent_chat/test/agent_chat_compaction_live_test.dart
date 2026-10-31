import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  String id,
  String type, {
  String status = 'completed',
  String createdAt = '2026-10-12T10:00:00Z',
  String text = '',
  Map<String, Object?> normalized = const <String, Object?>{},
  Map<String, Object?> data = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': 'turn-1',
  'type': type,
  'status': status,
  'createdAt': createdAt,
  'updatedAt': createdAt,
  'text': text,
  'normalized': normalized,
  'data': data,
};

Map<String, Object?> _command(String id, String command) => _item(
  id,
  'command_execution',
  normalized: <String, Object?>{'command': command},
);

Map<String, Object?> _compaction(
  String status, {
  Map<String, Object?> data = const <String, Object?>{},
}) => _item(
  'k1',
  'context_compaction',
  status: status,
  createdAt: '2026-10-12T10:00:05Z',
  data: data,
);

AgentChatTurnSection _section(
  List<Map<String, Object?>> items, {
  bool running = true,
}) {
  final thread = AgentChatThread.fromSnapshot(
    AgentChatSnapshot.fromJson(<String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'cursor': 1,
      'session': <String, Object?>{
        'status': running ? 'running' : 'idle',
        if (running) 'activeTurnId': 'turn-1',
      },
      'turns': <Object?>[
        <String, Object?>{
          'turnId': 'turn-1',
          'status': running ? 'running' : 'completed',
          'startedAt': '2026-10-12T10:00:00Z',
          if (!running) 'completedAt': '2026-10-12T10:00:09Z',
        },
      ],
      'items': items,
    }),
  );
  return AgentChatTimelineProjection.build(thread).entries
      .whereType<AgentChatTurnEntry>()
      .single
      .section;
}

AgentChatItem _parsed(Map<String, Object?> json) =>
    AgentChatItem.fromJson(json);

void main() {
  group('live row', () {
    test('a running compaction owns the live row', () {
      final live = _section(<Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Go'),
        _command('c1', 'make'),
        _item('r1', 'reasoning', text: 'Now I will compact the context.'),
        _compaction('inProgress'),
      ]).liveWork!;
      expect(live.compaction?.id, 'k1');
      expect(live.compacting, isTrue);
      expect(live.compactingSince, DateTime.utc(2026, 10, 12, 10, 0, 5));
      expect(live.label, 'Compacting');
      expect(live.current, isNull);
      expect(live.reasoning, isNull);
      expect(live.earlierCount, 1);
      // The earlier action and the stale reasoning sit behind the fold.
      expect(live.hiddenCount, 2);
    });

    test('a finished compaction gives the row back to the last action', () {
      final live = _section(<Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Go'),
        _command('c1', 'make'),
        _compaction('completed'),
      ]).liveWork!;
      expect(live.compaction, isNull);
      expect(live.compacting, isFalse);
      expect(live.compactingSince, isNull);
      expect(live.label, 'Ran make');
      expect(live.hiddenCount, 1);
    });

    test('a settled turn has no live row', () {
      final section = _section(<Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Go'),
        _compaction('inProgress'),
      ], running: false);
      expect(section.liveWork, isNull);
    });
  });

  test('the compacting label counts from the compaction start', () {
    final since = DateTime.utc(2026, 10, 12, 10);
    expect(
      agentChatCompactingLabel(
        since,
        now: since.add(const Duration(seconds: 12)),
      ),
      'Compacting for 12s',
    );
    expect(
      agentChatCompactingLabel(
        since,
        now: since.add(const Duration(seconds: 65)),
      ),
      'Compacting for 1m 5s',
    );
    expect(agentChatCompactingLabel(null, now: since), 'Compacting');
  });

  test('context token counts read at a glance', () {
    expect(agentChatContextTokenLabel(400), '400');
    expect(agentChatContextTokenLabel(1500), '1.5k');
    expect(agentChatContextTokenLabel(2000), '2k');
    expect(agentChatContextTokenLabel(120400), '120k');
    expect(agentChatContextTokenLabel(1250000), '1.3m');
    expect(agentChatContextTokenLabel(2000000), '2m');
  });

  test('compaction rows name how the compaction ended', () {
    expect(
      agentChatCompactionLabel(_parsed(_compaction('inProgress'))),
      'Compacting context',
    );
    expect(
      agentChatCompactionLabel(_parsed(_compaction('completed'))),
      'Compacted context',
    );
    expect(
      agentChatCompactionLabel(
        _parsed(
          _compaction(
            'completed',
            data: <String, Object?>{'preTokens': 1500, 'postTokens': 400},
          ),
        ),
      ),
      'Compacted context (1.5k → 400 tokens)',
    );
    expect(
      agentChatCompactionLabel(
        _parsed(
          _compaction('failed', data: <String, Object?>{'outcome': 'failed'}),
        ),
      ),
      'Compaction failed',
    );
    expect(
      agentChatCompactionLabel(
        _parsed(
          _compaction('failed', data: <String, Object?>{'outcome': 'stopped'}),
        ),
      ),
      'Compaction stopped',
    );
  });
}
