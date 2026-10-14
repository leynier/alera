import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  String id,
  String type, {
  String text = '',
  String status = 'completed',
  String createdAt = '2026-10-12T10:00:00Z',
  Map<String, Object?> normalized = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': 'turn-1',
  'type': type,
  'status': status,
  'createdAt': createdAt,
  'updatedAt': createdAt,
  'text': text,
  'normalized': normalized,
};

Map<String, Object?> _command(String id, String command, {String? status}) =>
    _item(
      id,
      'command_execution',
      status: status ?? 'completed',
      normalized: <String, Object?>{'command': command},
    );

Map<String, Object?> _edit(String id, String path, {String status = 'completed'}) =>
    _item(
      id,
      'file_change',
      status: status,
      normalized: <String, Object?>{
        'changes': <Object?>[
          <String, Object?>{'path': path, 'kind': 'update', 'diff': '+a\n-b'},
        ],
      },
    );

AgentChatThread _thread(
  List<Map<String, Object?>> items, {
  String? activeTurnId,
  Map<String, Object?>? turn,
  List<Map<String, Object?>> requests = const <Map<String, Object?>>[],
}) => AgentChatThread.fromSnapshot(
  AgentChatSnapshot.fromJson(<String, Object?>{
    'chatId': 'chat-1',
    'workspaceId': 'ws-1',
    'cursor': 1,
    'session': <String, Object?>{
      'status': activeTurnId == null ? 'idle' : 'running',
      'activeTurnId': ?activeTurnId,
    },
    'turns': <Object?>[?turn],
    'items': items,
    'pendingRequests': requests,
  }),
);

Map<String, Object?> _turn(String status, {String? reason}) => <String, Object?>{
  'turnId': 'turn-1',
  'status': status,
  'startedAt': '2026-10-12T10:00:00Z',
  'completedAt': '2026-10-12T10:00:03Z',
  'reason': ?reason,
};

AgentChatTurnSection _section(AgentChatThread thread) =>
    AgentChatTimelineProjection.build(
      thread,
    ).entries.whereType<AgentChatTurnEntry>().single.section;

final List<Map<String, Object?>> _work = <Map<String, Object?>>[
  _item('u1', 'user_message', text: 'Fix it'),
  _command('c1', 'make'),
  _command('c2', 'make test'),
  _item('a1', 'assistant_message', text: 'Done.'),
];

void main() {
  group('settled turns', () {
    test('a succeeded turn with several actions folds', () {
      final section = _section(_thread(_work, turn: _turn('completed')));
      expect(section.outcome, AgentChatTurnOutcome.succeeded);
      expect(section.collapsedByDefault, isTrue);
      expect(section.failed, isFalse);
      expect(
        agentChatTurnHeaderLabel(section, now: DateTime.utc(2030)),
        'Worked for 3s',
      );
    });

    final cases = <(String, String?, AgentChatTurnOutcome, String)>[
      ('failed', null, AgentChatTurnOutcome.failed, 'Failed after 3s'),
      ('cancelled', null, AgentChatTurnOutcome.cancelled, 'Cancelled after 3s'),
      ('interrupted', null, AgentChatTurnOutcome.stopped, 'Stopped after 3s'),
      (
        'interrupted',
        'runtimeRestarted',
        AgentChatTurnOutcome.interruptedByRestart,
        'Interrupted when the runtime restarted',
      ),
    ];
    for (final (status, reason, outcome, label) in cases) {
      test('a $outcome turn stays unfolded', () {
        final section = _section(
          _thread(_work, turn: _turn(status, reason: reason)),
        );
        expect(section.outcome, outcome);
        expect(section.failed, isTrue);
        expect(section.collapsedByDefault, isFalse);
        expect(section.liveWork, isNull);
        expect(agentChatTurnHeaderLabel(section, now: DateTime.utc(2030)), label);
      });
    }

    test('changed files keep one entry per path, newest last', () {
      final section = _section(
        _thread(<Map<String, Object?>>[
          _item('u1', 'user_message', text: 'Edit'),
          _edit('f1', 'lib/a.dart'),
          _edit('f2', 'lib/b.dart'),
          _edit('f3', 'lib/c.dart', status: 'failed'),
          _edit('f4', 'lib/a.dart'),
        ], turn: _turn('completed')),
      );
      expect(section.changedFiles.map((change) => change.path), <String>[
        'lib/b.dart',
        'lib/a.dart',
      ]);
      expect(agentChatChangedFilesLabel(2), 'Changed Files (2)');
    });
  });

  group('running turns', () {
    test('the live row names the current action in the present tense', () {
      final section = _section(
        _thread(<Map<String, Object?>>[
          _item('u1', 'user_message', text: 'Go'),
          _command('c1', 'make'),
          _item('n1', 'assistant_message', text: 'Building first.'),
          _command('c2', 'make lint'),
          _command('c3', 'make test', status: 'inProgress'),
        ], activeTurnId: 'turn-1'),
      );
      final live = section.liveWork!;
      expect(live.label, 'Running make test');
      expect(live.current?.item.id, 'c3');
      expect(live.earlierCount, 2);
      expect(live.earlierLabel, '2 earlier actions');
      expect(live.narration.map((item) => item.id), <String>['n1']);
      expect(section.collapsedByDefault, isTrue);
      expect(section.canToggleActivity, isTrue);
    });

    test('a failed last action reads Thinking and joins the disclosure', () {
      final section = _section(
        _thread(<Map<String, Object?>>[
          _item('u1', 'user_message', text: 'Go'),
          _command('c1', 'make'),
          _command('c2', 'make test', status: 'failed'),
        ], activeTurnId: 'turn-1'),
      );
      final live = section.liveWork!;
      expect(live.label, 'Thinking');
      expect(live.current, isNull);
      expect(live.lastActionFailed, isTrue);
      expect(live.earlierCount, 2);
    });

    test('reasoning after a finished action reads Thinking with a snippet', () {
      final section = _section(
        _thread(<Map<String, Object?>>[
          _item('u1', 'user_message', text: 'Go'),
          _command('c1', 'make'),
          _item(
            'r1',
            'reasoning',
            status: 'inProgress',
            text: 'The linker fails. Next I check flags.',
          ),
        ], activeTurnId: 'turn-1'),
      );
      final live = section.liveWork!;
      expect(live.label, 'Thinking');
      expect(live.reasoning, 'The linker fails.');
      expect(live.earlierCount, 1);
      // The rest of the reasoning is behind the disclosure too.
      expect(live.hiddenCount, 2);
    });

    test('the live clock counts from the turn start', () {
      final section = _section(
        _thread(
          <Map<String, Object?>>[
            _item('u1', 'user_message', text: 'Go'),
            _command('c1', 'make', status: 'inProgress'),
          ],
          activeTurnId: 'turn-1',
          turn: <String, Object?>{
            'turnId': 'turn-1',
            'status': 'running',
            'startedAt': '2026-10-12T10:00:00Z',
          },
        ),
      );
      expect(
        agentChatTurnHeaderLabel(
          section,
          now: DateTime.utc(2026, 10, 12, 10, 0, 4),
        ),
        'Working for 4s',
      );
    });
  });

  group('labels', () {
    test('live labels drop line counts and use the present tense', () {
      final edit = AgentChatWorkedAction.fromItem(
        AgentChatItem.fromJson(_edit('f1', 'lib/main.dart')),
      );
      expect(edit.label, 'Edited main.dart +1 -1');
      expect(agentChatWorkedActionLiveLabel(edit), 'Editing main.dart');
    });

    test('reasoning snippets take the first sentence of the first line', () {
      expect(
        agentChatReasoningSnippet('**Inspecting files**\n\nI need to look.'),
        'Inspecting files',
      );
      expect(agentChatReasoningSnippet('One. Two.'), 'One.');
      expect(agentChatReasoningSnippet('  \n '), isNull);
      final long = agentChatReasoningSnippet('a' * 300, maxLength: 20)!;
      expect(long.length, 20);
      expect(long.endsWith('…'), isTrue);
    });

    test('reasoning reads Thought once finished', () {
      final done = AgentChatItem.fromJson(_item('r1', 'reasoning'));
      final live = AgentChatItem.fromJson(
        _item('r2', 'reasoning', status: 'inProgress'),
      );
      expect(agentChatReasoningLabel(done), 'Thought');
      expect(agentChatReasoningLabel(live), 'Thinking');
    });

    test('long messages collapse past 8 lines or 600 characters', () {
      expect(agentChatMessageCollapses('short'), isFalse);
      expect(agentChatMessageCollapses(List.filled(8, 'x').join('\n')), isFalse);
      expect(agentChatMessageCollapses(List.filled(9, 'x').join('\n')), isTrue);
      expect(agentChatMessageCollapses('x' * 600), isFalse);
      expect(agentChatMessageCollapses('x' * 601), isTrue);
    });

    test('fold keys are stable per part', () {
      expect(agentChatTurnFoldKey('t1'), 'turn-t1');
      expect(agentChatActionFoldKey('i1'), 'action-i1');
      expect(agentChatReasoningFoldKey('i1'), 'reasoning-i1');
      expect(agentChatMessageFoldKey('i1'), 'message-i1');
      expect(agentChatChangedFilesFoldKey('t1'), 'changes-t1');
    });
  });

  test('unchanged pending requests keep the same dock list', () {
    final thread = _thread(
      _work,
      requests: <Map<String, Object?>>[
        <String, Object?>{
          'requestId': 'a1',
          'kind': 'command_execution_approval',
          'createdAt': '2026-10-12T10:00:00Z',
        },
      ],
    );
    final before = AgentChatTimelineProjection.build(thread);
    final after = AgentChatTimelineProjection.build(thread, previous: before);
    expect(identical(before.requests, after.requests), isTrue);
  });
}
