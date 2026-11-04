import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  String id, {
  String type = 'assistant_message',
  String? turnId = 'turn-1',
  String text = '',
  String status = 'completed',
  bool streaming = false,
  String? clientMessageId,
}) => <String, Object?>{
  'itemId': id,
  'turnId': ?turnId,
  'type': type,
  'status': status,
  'streaming': streaming,
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:01Z',
  'text': text,
  'clientMessageId': ?clientMessageId,
};

AgentChatThread _thread({
  int cursor = 4,
  List<Map<String, Object?>> items = const <Map<String, Object?>>[],
  Map<String, Object?>? recovery,
}) => AgentChatThread.fromSnapshot(
  AgentChatSnapshot.fromJson(<String, Object?>{
    'chatId': 'chat-1',
    'workspaceId': 'ws-1',
    'tabId': 'tab-1',
    'provider': 'codex',
    'providerInstanceId': 'codex',
    'title': 'Fix tests',
    'cursor': cursor,
    'session': <String, Object?>{
      'status': 'ready',
      'runtimeMode': 'approval-required',
      'interactionMode': 'default',
    },
    'items': items,
    'recovery': ?recovery,
  }),
);

AgentChatChange _change(int cursor, Map<String, Object?> delta) =>
    AgentChatChange.fromJson(<String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'cursor': cursor,
      'delta': delta,
    });

AgentChatThread _applied(AgentChatThread thread, AgentChatChange change) {
  final outcome = thread.apply(change);
  expect(outcome, isA<AgentChatApplied>());
  return (outcome as AgentChatApplied).thread;
}

void main() {
  test('ignores stale and foreign changes and reports skipped cursors', () {
    final thread = _thread();
    expect(thread.apply(_change(4, const {})), isA<AgentChatIgnored>());
    expect(thread.apply(_change(2, const {})), isA<AgentChatIgnored>());
    expect(
      thread.apply(
        AgentChatChange.fromJson(<String, Object?>{
          'chatId': 'other',
          'cursor': 5,
          'delta': <String, Object?>{},
        }),
      ),
      isA<AgentChatIgnored>(),
    );
    final gap = thread.apply(_change(6, const {}));
    expect(gap, isA<AgentChatGapNeedsSnapshot>());
  });

  test('upserts in place, appends new items and honors removals', () {
    final thread = _thread(
      items: <Map<String, Object?>>[
        _item('a', text: 'first'),
        _item('b', text: 'second'),
        _item('c', text: 'third'),
      ],
    );
    final next = _applied(
      thread,
      _change(5, <String, Object?>{
        'items': <Object?>[
          _item('b', text: 'second, edited'),
          _item('d', text: 'fourth'),
        ],
        'removedItemIds': <Object?>['a'],
      }),
    );
    expect(next.cursor, 5);
    expect(next.items.map((item) => item.id), <String>['b', 'c', 'd']);
    expect(next.itemById('b')!.text, 'second, edited');
    expect(thread.items, hasLength(3), reason: 'threads are immutable');
  });

  test('appends streamed text by offset and drops replays', () {
    final thread = _thread(
      items: <Map<String, Object?>>[_item('a', text: 'Hel', streaming: true)],
    );
    final next = _applied(
      thread,
      _change(5, <String, Object?>{
        'textAppends': <Object?>[
          <String, Object?>{
            'itemId': 'a',
            'stream': 'text',
            'offset': 3,
            'text': 'lo',
          },
          // A replay of the same append ends inside the text already there.
          <String, Object?>{
            'itemId': 'a',
            'stream': 'text',
            'offset': 3,
            'text': 'lo',
          },
          // An overlapping append contributes only its new tail.
          <String, Object?>{
            'itemId': 'a',
            'stream': 'text',
            'offset': 4,
            'text': 'o, world',
          },
          <String, Object?>{
            'itemId': 'a',
            'stream': 'reasoningText',
            'offset': 0,
            'text': 'thinking',
          },
          <String, Object?>{
            'itemId': 'a',
            'stream': 'output',
            'offset': 0,
            'text': 'ok',
          },
        ],
      }),
    );
    final item = next.itemById('a')!;
    expect(item.text, 'Hello, world');
    expect(item.reasoningText, 'thinking');
    expect(item.output, 'ok');
  });

  test('a misaligned or orphaned append needs a snapshot', () {
    final thread = _thread(
      items: <Map<String, Object?>>[_item('a', text: 'x')],
    );
    expect(
      thread.apply(
        _change(5, <String, Object?>{
          'textAppends': <Object?>[
            <String, Object?>{
              'itemId': 'a',
              'stream': 'text',
              'offset': 5,
              'text': 'late',
            },
          ],
        }),
      ),
      isA<AgentChatGapNeedsSnapshot>(),
    );
    expect(
      thread.apply(
        _change(5, <String, Object?>{
          'textAppends': <Object?>[
            <String, Object?>{
              'itemId': 'missing',
              'stream': 'text',
              'offset': 0,
              'text': 'x',
            },
          ],
        }),
      ),
      isA<AgentChatGapNeedsSnapshot>(),
    );
  });

  test('replaces requests and queue as full lists and keeps absent ones', () {
    final thread = _applied(
      _thread(),
      _change(5, <String, Object?>{
        'requests': <Object?>[
          <String, Object?>{
            'requestId': 'r1',
            'kind': 'command_execution_approval',
            'createdAt': '2026-10-12T10:00:00Z',
            'command': 'rm -rf build',
            'decisions': <Object?>['accept', 'acceptForSession', 'decline'],
          },
        ],
        'queue': <Object?>[
          <String, Object?>{
            'queueId': 'q1',
            'clientMessageId': 'm1',
            'text': 'next',
            'createdAt': '2026-10-12T10:00:00Z',
          },
        ],
      }),
    );
    expect(thread.pendingRequests.single.decisions, <AgentChatApprovalDecision>[
      AgentChatApprovalDecision.accept,
      AgentChatApprovalDecision.acceptForSession,
      AgentChatApprovalDecision.decline,
    ]);
    expect(thread.queue.single.queueId, 'q1');
    expect(thread.containsClientMessage('m1'), isTrue);
    final unchanged = _applied(thread, _change(6, <String, Object?>{}));
    expect(unchanged.pendingRequests, hasLength(1));
    expect(unchanged.queue, hasLength(1));
    final cleared = _applied(
      unchanged,
      _change(7, <String, Object?>{
        'requests': <Object?>[],
        'queue': <Object?>[],
      }),
    );
    expect(cleared.pendingRequests, isEmpty);
    expect(cleared.queue, isEmpty);
  });

  test('recovery is cleared only when the delta names it', () {
    final thread = _thread(
      recovery: <String, Object?>{
        'kind': 'resumable',
        'message': 'The runtime restarted.',
        'canResume': true,
      },
    );
    final kept = _applied(thread, _change(5, <String, Object?>{'title': 'T'}));
    expect(kept.recovery?.kind, AgentChatRecoveryKind.resumable);
    expect(kept.title, 'T');
    final cleared = _applied(
      kept,
      _change(6, <String, Object?>{'recovery': null}),
    );
    expect(cleared.recovery, isNull);
  });

  test('a provider switch updates identity and session together', () {
    final next = _applied(
      _thread(),
      _change(5, <String, Object?>{
        'provider': 'claudeAgent',
        'providerInstanceId': 'claudeAgent',
        'session': <String, Object?>{
          'status': 'ready',
          'generation': 2,
          'model': 'opus',
          'runtimeMode': 'full-access',
          'interactionMode': 'plan',
          'capabilities': <String, Object?>{'steer': true, 'interrupt': true},
        },
      }),
    );
    expect(next.provider, 'claudeAgent');
    expect(next.session.generation, 2);
    expect(next.session.runtimeMode, AgentChatRuntimeMode.fullAccess);
    expect(next.session.interactionMode, AgentChatInteractionMode.plan);
    expect(next.session.capabilities.steer, isTrue);
  });

  test('history pages prepend without duplicating loaded items', () {
    final thread = _thread(
      items: <Map<String, Object?>>[_item('c'), _item('d')],
    );
    final page = AgentChatHistoryPage.fromJson(<String, Object?>{
      'items': <Object?>[_item('a'), _item('b'), _item('c', text: 'stale')],
      'turns': <Object?>[
        <String, Object?>{'turnId': 'turn-0', 'status': 'completed'},
      ],
      'historyBefore': 'cursor-a',
    });
    final next = thread.prependHistory(page);
    expect(next.items.map((item) => item.id), <String>['a', 'b', 'c', 'd']);
    expect(next.itemById('c')!.text, isEmpty, reason: 'live copy wins');
    expect(next.historyBefore, 'cursor-a');
    expect(next.turnById('turn-0'), isNotNull);
  });
}
