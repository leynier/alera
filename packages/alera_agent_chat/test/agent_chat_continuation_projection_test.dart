import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  String id, {
  String type = 'assistant_message',
  String? turnId = 'turn-1',
  String text = '',
  String reasoningText = '',
  String output = '',
  String status = 'completed',
  bool streaming = false,
  String updatedAt = '2026-10-12T10:00:00Z',
  Map<String, Object?> normalized = const <String, Object?>{},
  Map<String, Object?> fields = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': ?turnId,
  'type': type,
  'status': status,
  'streaming': streaming,
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': updatedAt,
  'text': text,
  'reasoningText': reasoningText,
  'output': output,
  'normalized': normalized,
  ...fields,
};

Map<String, Object?> _segment(
  String parentId,
  Object? index, {
  String type = 'assistant_message',
  String? stream = 'text',
  String text = '',
  String reasoningText = '',
  String output = '',
  String status = 'completed',
  bool streaming = false,
  String? turnId = 'turn-1',
  Map<String, Object?> normalized = const <String, Object?>{},
  Map<String, Object?> fields = const <String, Object?>{},
}) => _item(
  '$parentId:segment:${stream ?? 'text'}:$index',
  type: type,
  turnId: turnId,
  text: text,
  reasoningText: reasoningText,
  output: output,
  status: status,
  streaming: streaming,
  normalized: <String, Object?>{
    'continuationOf': parentId,
    'segmentIndex': index,
    'stream': ?stream,
    ...normalized,
  },
  fields: fields,
);

AgentChatThread _thread(List<Map<String, Object?>> items) =>
    AgentChatThread.fromSnapshot(
      AgentChatSnapshot.fromJson(<String, Object?>{
        'chatId': 'chat-1',
        'workspaceId': 'ws-1',
        'cursor': 1,
        'items': items,
      }),
    );

AgentChatTurnSection _section(AgentChatTimelineProjection projection) =>
    projection.sectionFor('turn-1')!;

void main() {
  test('recalls full segmented prompts and preserves the canonical head', () {
    final thread = _thread(<Map<String, Object?>>[
      _item(
        'user',
        type: 'user_message',
        text: 'First ',
        normalized: <String, Object?>{'segmentCount': 3},
        fields: <String, Object?>{
          'clientMessageId': 'client-1',
          'data': <String, Object?>{'native': 'kept'},
          'attachments': <Object?>[
            <String, Object?>{'type': 'file', 'path': '/w/readme.md'},
          ],
        },
      ),
      _segment('user', 1, type: 'user_message', stream: null, text: '🙂 '),
      _segment('user', 2, type: 'user_message', text: 'last'),
    ]);
    final projection = AgentChatTimelineProjection.build(thread);
    final prompt = _section(projection).prompts.single;
    expect(prompt.id, 'user');
    expect(prompt.clientMessageId, 'client-1');
    expect(prompt.text, 'First 🙂 last');
    expect(prompt.isPartialContinuation, isFalse);
    expect(prompt.attachments.single.path, '/w/readme.md');
    expect(identical(prompt.data, thread.items.first.data), isTrue);
    expect(identical(prompt.normalized, thread.items.first.normalized), isTrue);
    expect(projection.promptHistory, <String>['First 🙂 last']);
    expect(thread.items, hasLength(3));
    expect(thread.items.first.text, 'First ');
  });

  test('joins late segments at the head without merging other answers', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        _item('a', text: '```dart\nfinal value = '),
        _item('command', type: 'command_execution'),
        _item('separate', text: 'A separate answer'),
        _segment('a', 1, text: "'🙂';\n```"),
      ]),
    );
    final section = _section(projection);
    final narration = (section.activity.first as AgentChatItemRow).item;
    expect(narration.id, 'a');
    expect(narration.text, "```dart\nfinal value = '🙂';\n```");
    expect(section.answers.single.id, 'separate');
  });

  test('joins independent stream indices into one logical item', () {
    final section = _section(
      AgentChatTimelineProjection.build(
        _thread(<Map<String, Object?>>[
          _item('a', text: 't0', reasoningText: 'r0', output: 'o0'),
          _segment('a', 1, stream: 'reasoningText', reasoningText: 'r1'),
          _segment('a', 1, text: 't1'),
          _segment('a', 1, stream: 'output', output: 'o1'),
          _segment('a', 2, stream: 'reasoningText', reasoningText: 'r2'),
        ]),
      ),
    );
    final answer = section.answers.single;
    expect(answer.id, 'a');
    expect(answer.text, 't0t1');
    expect(answer.reasoningText, 'r0r1r2');
    expect(answer.output, 'o0o1');
    expect(answer.isPartialContinuation, isFalse);
  });

  test('unrelated user steers remain separate from segmented prompts', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        _item('user', type: 'user_message', text: 'Start '),
        _segment('user', 1, type: 'user_message', text: 'here'),
        _item('a', text: 'Working'),
        _item('steer', type: 'user_message', text: 'Also add tests'),
        _segment('steer', 1, type: 'user_message', text: ' please'),
      ]),
    );
    final section = _section(projection);
    expect(section.prompts.single.text, 'Start here');
    expect(section.answers.map((item) => item.id), <String>['a', 'steer']);
    expect(section.answers.last.text, 'Also add tests please');
    expect(projection.promptHistory, <String>['Start here']);
  });

  test('orphan segments remain visible until history provides the head', () {
    final thread = _thread(<Map<String, Object?>>[
      _segment('user', 1, type: 'user_message', text: 'middle '),
      _segment('user', 2, type: 'user_message', text: 'last'),
    ]);
    final before = AgentChatTimelineProjection.build(thread);
    expect(_section(before).prompts.single.text, 'middle last');
    expect(_section(before).prompts.single.isPartialContinuation, isTrue);
    expect(before.promptHistory, isEmpty);
    final loaded = thread.prependHistory(
      AgentChatHistoryPage.fromJson(<String, Object?>{
        'items': <Object?>[
          _item(
            'user',
            type: 'user_message',
            text: 'first ',
            normalized: <String, Object?>{'segmentCount': 3},
          ),
          _segment('user', 1, type: 'user_message', text: 'stale history'),
        ],
      }),
    );
    final after = AgentChatTimelineProjection.build(loaded, previous: before);
    expect(_section(after).prompts.single.id, 'user');
    expect(_section(after).prompts.single.isPartialContinuation, isFalse);
    expect(after.promptHistory, <String>['first middle last']);
  });

  test('a missing middle segment never joins Markdown across the gap', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        _item('a', text: '```dart\n'),
        _segment('a', 2, text: '```\nSuffix'),
        _segment('a', 3, text: ' continues'),
      ]),
    );
    final answers = _section(projection).answers;
    expect(answers, hasLength(2));
    expect(answers.first.text, '```dart\n');
    expect(answers.last.text, '```\nSuffix continues');
    expect(answers.every((item) => item.isPartialContinuation), isTrue);
  });

  test('declared missing suffix is partial and excluded from recall', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        _item(
          'user',
          type: 'user_message',
          text: 'first ',
          normalized: <String, Object?>{'segmentCount': 3},
        ),
        _segment('user', 1, type: 'user_message', text: 'middle'),
      ]),
    );
    expect(_section(projection).prompts.single.text, 'first middle');
    expect(_section(projection).prompts.single.isPartialContinuation, isTrue);
    expect(projection.promptHistory, isEmpty);
  });

  for (final index in <Object?>[0, -1, 1.0, '1', null]) {
    test('rejects non-positive or non-integer index $index', () {
      final projection = AgentChatTimelineProjection.build(
        _thread(<Map<String, Object?>>[
          _item('a', text: 'head'),
          _segment('a', index, text: 'untrusted'),
        ]),
      );
      expect(_section(projection).answers, hasLength(2));
      expect(_section(projection).answers.last.isPartialContinuation, isTrue);
    });
  }

  final mismatches = <String, Map<String, Object?>>{
    'turn': <String, Object?>{'turnId': 'other-turn'},
    'type': <String, Object?>{'type': 'user_message'},
    'actor': <String, Object?>{'actor': 'someone-else'},
    'origin': <String, Object?>{
      'normalized': <String, Object?>{
        'continuationOf': 'a',
        'segmentIndex': 1,
        'stream': 'text',
        'origin': <String, Object?>{'kind': 'chatMessage', 'senderChatId': 'x'},
      },
    },
    'command': <String, Object?>{
      'normalized': <String, Object?>{
        'continuationOf': 'a',
        'segmentIndex': 1,
        'stream': 'text',
        'command': 'different command',
      },
    },
    'raw data': <String, Object?>{
      'data': <String, Object?>{'different': true},
    },
    'client message': <String, Object?>{'clientMessageId': 'unexpected'},
  };
  for (final mismatch in mismatches.entries) {
    test('does not merge a continuation with mismatched ${mismatch.key}', () {
      final projection = AgentChatTimelineProjection.build(
        _thread(<Map<String, Object?>>[
          _item('a', text: 'head'),
          <String, Object?>{
            ..._segment('a', 1, text: 'different'),
            ...mismatch.value,
          },
        ]),
      );
      final items = <AgentChatItem>[
        for (final entry in projection.entries.whereType<AgentChatTurnEntry>())
          ...entry.section.sourceItems,
      ];
      expect(items, hasLength(2));
      expect(items.first.text, 'head');
      expect(items.last.text, 'different');
    });
  }

  test('automated origins survive joining and stay out of prompt history', () {
    final origin = <String, Object?>{
      'kind': 'orchestrationWake',
      'senderChatId': 'parent',
      'taskIds': <Object?>['task'],
    };
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        _item(
          'wake',
          type: 'user_message',
          text: 'Tasks ',
          normalized: <String, Object?>{'origin': origin},
        ),
        _segment(
          'wake',
          1,
          type: 'user_message',
          text: 'finished',
          normalized: <String, Object?>{'origin': Map.of(origin)},
        ),
      ]),
    );
    expect(_section(projection).prompts.single.text, 'Tasks finished');
    expect(_section(projection).prompts.single.isAutomatedInput, isTrue);
    expect(projection.promptHistory, isEmpty);
  });

  test(
    'live UTF-16 appends keep wire identity and reuse unchanged sections',
    () {
      final first = _thread(<Map<String, Object?>>[
        _item('a', text: 'Hello🙂 '),
        _segment('a', 1, text: 'a🙂', status: 'inProgress', streaming: true),
        _item('old', turnId: 'other-turn', text: 'Earlier '),
        _segment('old', 1, turnId: 'other-turn', text: 'answer'),
      ]);
      final before = AgentChatTimelineProjection.build(first);
      final tailId = first.items[1].id;
      final appended = first.apply(
        AgentChatChange.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'cursor': 2,
          'delta': <String, Object?>{
            'textAppends': <Object?>[
              <String, Object?>{
                'itemId': tailId,
                'stream': 'text',
                'offset': 3,
                'text': '🚀',
              },
            ],
          },
        }),
      ) as AgentChatApplied;
      final during = AgentChatTimelineProjection.build(
        appended.thread,
        previous: before,
      );
      expect(appended.thread.itemById(tailId)!.text, 'a🙂🚀');
      expect(appended.thread.itemById('a')!.text, 'Hello🙂 ');
      expect(_section(during).answers.single.id, 'a');
      expect(_section(during).answers.single.text, 'Hello🙂 a🙂🚀');
      expect(_section(during).answers.single.isInProgress, isTrue);
      expect(
        identical(
          before.sectionFor('other-turn'),
          during.sectionFor('other-turn'),
        ),
        isTrue,
      );
      final completed = appended.thread.apply(
        AgentChatChange.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'cursor': 3,
          'delta': <String, Object?>{
            'items': <Object?>[_segment('a', 1, text: 'a🙂🚀')],
          },
        }),
      ) as AgentChatApplied;
      final after = AgentChatTimelineProjection.build(
        completed.thread,
        previous: during,
      );
      expect(_section(after).answers.single.text, 'Hello🙂 a🙂🚀');
      expect(
        _section(after).answers.single.status,
        AgentChatItemStatus.completed,
      );
      expect(_section(after).answers.single.isInProgress, isFalse);
    },
  );

  for (final status in <String>['failed', 'declined']) {
    test('$status segments retain failure without a streaming shimmer', () {
      final answer = _section(
        AgentChatTimelineProjection.build(
          _thread(<Map<String, Object?>>[
            _item('a', text: 'First '),
            _segment('a', 1, text: 'last', status: status, streaming: true),
          ]),
        ),
      ).answers.single;
      expect(answer.text, 'First last');
      expect(answer.isFailed, isTrue);
      expect(answer.isInProgress, isFalse);
    });
  }

  test('reasoning and command output retain one worked row per item', () {
    final section = _section(
      AgentChatTimelineProjection.build(
        _thread(<Map<String, Object?>>[
          _item('reason', type: 'reasoning', reasoningText: 'Think '),
          _segment(
            'reason',
            1,
            type: 'reasoning',
            stream: 'reasoningText',
            reasoningText: 'more',
          ),
          _item(
            'command',
            type: 'command_execution',
            output: 'first\n',
            normalized: <String, Object?>{'command': 'make test'},
          ),
          _segment(
            'command',
            1,
            type: 'command_execution',
            stream: 'output',
            output: 'last\n',
          ),
        ]),
      ),
    );
    expect(section.activity, hasLength(2));
    expect(
      (section.activity.first as AgentChatItemRow).item.reasoningText,
      'Think more',
    );
    final command =
        (section.activity.last as AgentChatActionGroupRow).actions.single.item;
    expect(command.command, 'make test');
    expect(command.output, 'first\nlast\n');
  });

  test('different future wire types cannot merge through unknown fallback', () {
    final section = _section(
      AgentChatTimelineProjection.build(
        _thread(<Map<String, Object?>>[
          _item('unknown', type: 'future_a', output: 'first'),
          _segment(
            'unknown',
            1,
            type: 'future_b',
            stream: 'output',
            output: 'last',
          ),
        ]),
      ),
    );
    expect(section.sourceItems, hasLength(2));
    expect(section.sourceItems.map((item) => item.wireType), <String>[
      'future_a',
      'future_b',
    ]);
  });

  test(
    'hides only explicit payload rows and keeps them in the wire thread',
    () {
      final payloadRef = <String, Object?>{
        'itemId': 'a:payload:1',
        'segmentCount': 1,
        'format': 'json',
      };
      final thread = _thread(<Map<String, Object?>>[
        _item(
          'a',
          text: 'Answer',
          normalized: <String, Object?>{'payloadRef': payloadRef},
        ),
        _item(
          'a:payload:1',
          type: 'payload',
          text: '{"raw":"kept"}',
          normalized: <String, Object?>{'hidden': true},
        ),
        _item(
          'future',
          type: 'future',
          normalized: <String, Object?>{'hidden': true},
        ),
        _item('visible-payload', type: 'payload'),
      ]);
      final section = _section(AgentChatTimelineProjection.build(thread));
      expect(section.sourceItems.map((item) => item.id), <String>[
        'a',
        'future',
        'visible-payload',
      ]);
      expect(section.sourceItems.first.normalized['payloadRef'], payloadRef);
      expect(thread.itemById('a:payload:1')!.text, '{"raw":"kept"}');
      expect(thread.items, hasLength(4));
    },
  );
}
