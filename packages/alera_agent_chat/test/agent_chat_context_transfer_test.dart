import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

String _at(int minute) =>
    DateTime.utc(2026, 10, 26, 10, minute).toIso8601String();

Map<String, Object?> _transfer(
  String id,
  String kind, {
  String source = 'source',
  String target = 'chat',
  String status = 'consumed',
  int minute = 0,
  String? sourceTurnId,
  String? targetTurnId,
  String? itemId,
  String? sourceTitle,
  String? error,
}) => <String, Object?>{
  'transferId': id,
  'kind': kind,
  'sourceChatId': source,
  'targetChatId': target,
  'status': status,
  'createdAt': _at(minute),
  'updatedAt': _at(minute),
  'sourceTurnId': ?sourceTurnId,
  'targetTurnId': ?targetTurnId,
  'itemId': ?itemId,
  'sourceTitle': ?sourceTitle,
  'error': ?error,
};

Map<String, Object?> _item(
  String id,
  String type, {
  String? turnId,
  int minute = 0,
  Map<String, Object?> normalized = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': ?turnId,
  'type': type,
  'status': 'completed',
  'createdAt': _at(minute),
  'updatedAt': _at(minute),
  'text': 'Text $id',
  'normalized': normalized,
};

Map<String, Object?> _turn(String id, int minute) => <String, Object?>{
  'turnId': id,
  'status': 'completed',
  'startedAt': _at(minute),
  'completedAt': _at(minute),
};

AgentChatThread _thread({
  List<Map<String, Object?>> items = const <Map<String, Object?>>[],
  List<Map<String, Object?>> turns = const <Map<String, Object?>>[],
  List<Map<String, Object?>> transfers = const <Map<String, Object?>>[],
  String? historyBefore,
}) => AgentChatThread.fromSnapshot(
  AgentChatSnapshot.fromJson(<String, Object?>{
    'chatId': 'chat',
    'workspaceId': 'ws',
    'cursor': 1,
    'session': <String, Object?>{'status': 'ready'},
    'turns': turns,
    'items': items,
    'contextTransfers': transfers,
    'historyBefore': ?historyBefore,
  }),
);

List<String> _keys(AgentChatThread thread) => <String>[
  for (final entry in AgentChatTimelineProjection.build(thread).entries)
    entry.key,
];

AgentChatSummary _chat(String id, String title, {bool archived = false}) =>
    AgentChatSummary.fromJson(<String, Object?>{
      'chatId': id,
      'workspaceId': 'ws',
      'title': title,
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'status': 'ready',
      'archived': archived,
      'updatedAt': _at(0),
    });

void main() {
  test('records parse with their endpoints and skip malformed entries', () {
    final transfers = agentChatTransfersFromJson(<Object?>[
      <String, Object?>{
        ..._transfer(
          't1',
          'providerHandoff',
          source: 'chat',
          status: 'pending',
        ),
        'from': <String, Object?>{'provider': 'codex', 'model': 'gpt-5'},
        'to': <String, Object?>{'provider': 'claudeAgent'},
      },
      <String, Object?>{'kind': 'fork'},
      _transfer('t2', 'teleport'),
    ]);
    expect(transfers.map((transfer) => transfer.id), <String>['t1', 't2']);
    final handoff = transfers.first;
    expect(handoff.kind, AgentChatTransferKind.providerHandoff);
    expect(handoff.crossChat, isFalse);
    expect(handoff.status, AgentChatTransferStatus.pending);
    expect(handoff.from?.model, 'gpt-5');
    expect(handoff.to?.provider, 'claudeAgent');
    expect(transfers.last.kind, AgentChatTransferKind.unknown);
  });

  test('status labels name a waiting merge-back and a failed result', () {
    final pending = AgentChatContextTransfer.tryParse(
      _transfer('m', 'mergeBack', status: 'pending'),
    )!;
    expect(pending.statusLabel, 'Waiting for Next Message');
    final failed = AgentChatContextTransfer.tryParse(
      _transfer('r', 'subagentResult', error: 'The task failed.'),
    )!;
    expect(failed.failed, isTrue);
    expect(failed.statusLabel, 'Failed');
    expect(AgentChatTransferKind.fork.label, 'Forked From');
  });

  test('a delta replaces the records and an absent key keeps them', () {
    final thread = _thread(
      transfers: <Map<String, Object?>>[
        _transfer('m', 'mergeBack', status: 'pending'),
      ],
    );
    final untouched = thread.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'chat',
        'cursor': 2,
        'delta': <String, Object?>{'title': 'Renamed'},
      }),
    );
    final kept = (untouched as AgentChatApplied).thread;
    expect(identical(kept.contextTransfers, thread.contextTransfers), isTrue);
    final settled = kept.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'chat',
        'cursor': 3,
        'delta': <String, Object?>{
          'contextTransfers': <Object?>[
            _transfer('m', 'mergeBack', targetTurnId: 'turn-2'),
          ],
        },
      }),
    );
    final transfer =
        (settled as AgentChatApplied).thread.contextTransfers.single;
    expect(transfer.status, AgentChatTransferStatus.consumed);
    expect(transfer.targetTurnId, 'turn-2');
  });

  test('lineage lists cross-chat transfers into the chat, newest first', () {
    final relations = agentChatTransferRelations(
      chatId: 'chat',
      transfers: agentChatTransfersFromJson(<Object?>[
        _transfer('fork', 'fork', sourceTitle: 'Old title', minute: 1),
        _transfer('handoff', 'providerHandoff', source: 'chat', minute: 2),
        _transfer('merge', 'mergeBack', source: 'gone', minute: 3),
        _transfer('result', 'subagentResult', source: 'child', minute: 4),
        _transfer('elsewhere', 'fork', target: 'other', minute: 5),
      ]),
      chats: <AgentChatSummary>[
        _chat('source', 'Source chat'),
        _chat('child', 'Child chat', archived: true),
      ],
    );
    expect(relations.map((relation) => relation.transfer.id), <String>[
      'result',
      'merge',
      'fork',
    ]);
    expect(relations[0].title, 'Child chat');
    expect(relations[0].missing, isTrue);
    expect(relations[1].title, 'Agent Chat');
    expect(relations[1].missing, isTrue);
    expect(relations[2].title, 'Source chat');
    expect(relations[2].missing, isFalse);
  });

  test('timeline rows sit where the context arrived', () {
    final thread = _thread(
      turns: <Map<String, Object?>>[
        _turn('turn-1', 1),
        _turn('turn-2', 3),
        _turn('turn-3', 6),
      ],
      items: <Map<String, Object?>>[
        _item('p1', 'user_message', turnId: 'turn-1', minute: 1),
        _item('p2', 'user_message', turnId: 'turn-2', minute: 3),
        _item(
          'notice',
          'notice',
          minute: 4,
          normalized: <String, Object?>{
            'mergeBack': <String, Object?>{'status': 'pending'},
          },
        ),
        _item('p3', 'user_message', turnId: 'turn-3', minute: 6),
      ],
      transfers: <Map<String, Object?>>[
        _transfer('fork', 'fork', sourceTurnId: 'turn-1', minute: 2),
        _transfer('handoff', 'providerHandoff', source: 'chat', minute: 3),
        _transfer('merge', 'mergeBack', itemId: 'notice', minute: 4),
        _transfer(
          'result',
          'subagentResult',
          targetTurnId: 'turn-3',
          minute: 6,
        ),
        _transfer('queued', 'subagentResult', minute: 5),
      ],
    );
    expect(_keys(thread), <String>[
      'turn-turn-1',
      'transfer-fork',
      'turn-turn-2',
      'transfer-merge',
      'transfer-queued',
      'transfer-result',
      'turn-turn-3',
    ]);
    final merge = AgentChatTimelineProjection.build(thread).entries
        .whereType<AgentChatTransferEntry>()
        .firstWhere((entry) => entry.transfer.id == 'merge');
    expect(merge.notice?.id, 'notice');
  });

  test('a row whose place is on an unloaded page waits for it', () {
    final thread = _thread(
      historyBefore: 'cursor',
      turns: <Map<String, Object?>>[_turn('turn-9', 9)],
      items: <Map<String, Object?>>[
        _item('p9', 'user_message', turnId: 'turn-9', minute: 9),
      ],
      transfers: <Map<String, Object?>>[
        _transfer('fork', 'fork', sourceTurnId: 'turn-1', minute: 2),
        _transfer('merge', 'mergeBack', itemId: 'old-notice', minute: 3),
        _transfer('late', 'subagentResult', minute: 10),
      ],
    );
    expect(_keys(thread), <String>['turn-turn-9', 'transfer-late']);
  });
}
