import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  String id,
  String type, {
  String? turnId = 'turn-1',
  String text = '',
  String status = 'completed',
  String createdAt = '2026-10-12T10:00:00Z',
  Map<String, Object?> normalized = const <String, Object?>{},
  String? clientMessageId,
}) => <String, Object?>{
  'itemId': id,
  'turnId': ?turnId,
  'type': type,
  'status': status,
  'createdAt': createdAt,
  'updatedAt': createdAt,
  'text': text,
  'normalized': normalized,
  'clientMessageId': ?clientMessageId,
};

AgentChatThread _thread(
  List<Map<String, Object?>> items, {
  String? activeTurnId,
  List<Map<String, Object?>> turns = const <Map<String, Object?>>[],
  List<Map<String, Object?>> requests = const <Map<String, Object?>>[],
}) => AgentChatThread.fromSnapshot(
  AgentChatSnapshot.fromJson(<String, Object?>{
    'chatId': 'chat-1',
    'workspaceId': 'ws-1',
    'cursor': 1,
    'session': <String, Object?>{
      'status': 'running',
      'activeTurnId': ?activeTurnId,
    },
    'turns': turns,
    'items': items,
    'pendingRequests': requests,
  }),
);

List<AgentChatTurnSection> _sections(AgentChatTimelineProjection projection) =>
    <AgentChatTurnSection>[
      for (final entry in projection.entries.whereType<AgentChatTurnEntry>())
        entry.section,
    ];

AgentChatTurnSection _section(AgentChatTimelineProjection projection) =>
    (projection.entries.whereType<AgentChatTurnEntry>().single).section;

void main() {
  test('retained payload alone makes an activity row expandable', () {
    final retained = AgentChatItem.fromJson(
      _item(
        'tool-1',
        'mcp_tool_call',
        normalized: <String, Object?>{
          'payloadRef': <String, Object?>{
            'itemId': 'tool-1:payload:1',
            'segmentCount': 3,
            'format': 'json',
          },
        },
      ),
    );
    expect(retained.hasDetails, isTrue);
    expect(
      AgentChatItem.fromJson(_item('tool-2', 'mcp_tool_call')).hasDetails,
      isFalse,
    );
  });

  test('splits a turn into prompt, worked activity and the final answer', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(
        <Map<String, Object?>>[
          _item('u1', 'user_message', text: 'Fix the build'),
          _item('a1', 'assistant_message', text: 'Looking at the logs.'),
          _item('r1', 'reasoning', text: 'The error is in main.'),
          _item(
            'c1',
            'command_execution',
            normalized: <String, Object?>{'command': 'make test'},
          ),
          _item(
            'f1',
            'file_change',
            normalized: <String, Object?>{
              'changes': <Object?>[
                <String, Object?>{
                  'path': 'lib/main.dart',
                  'kind': 'update',
                  'diff': '--- a\n+++ b\n+fixed\n-broken\n+again',
                },
              ],
            },
          ),
          _item('a2', 'assistant_message', text: 'Fixed it.'),
        ],
        turns: <Map<String, Object?>>[
          <String, Object?>{
            'turnId': 'turn-1',
            'status': 'completed',
            'startedAt': '2026-10-12T10:00:00Z',
            'completedAt': '2026-10-12T10:01:05Z',
          },
        ],
      ),
    );
    final section = _section(projection);
    expect(section.prompts.map((item) => item.id), <String>['u1']);
    expect(section.answers.map((item) => item.id), <String>['a2']);
    expect(section.activity, hasLength(3));
    expect((section.activity[0] as AgentChatItemRow).item.id, 'a1');
    expect((section.activity[1] as AgentChatItemRow).item.id, 'r1');
    final group = section.activity[2] as AgentChatActionGroupRow;
    expect(group.summary, 'Edited 1 file, ran 1 command');
    expect(group.actions.map((action) => action.label), <String>[
      'Ran make test',
      'Edited main.dart +2 -1',
    ]);
    expect(section.working, isFalse);
    expect(section.collapsedByDefault, isTrue);
    expect(agentChatDurationLabel(section.workedFor!), '1m 5s');
    expect(projection.promptHistory, <String>['Fix the build']);
  });

  test('a running turn stays expanded and keeps streaming text as answer', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Hi'),
        _item(
          'c1',
          'command_execution',
          status: 'inProgress',
          normalized: <String, Object?>{'command': 'ls'},
        ),
        _item('a1', 'assistant_message', text: 'Partial', status: 'inProgress'),
      ], activeTurnId: 'turn-1'),
    );
    final section = _section(projection);
    expect(section.working, isTrue);
    expect(section.collapsedByDefault, isFalse);
    expect(section.answers.single.id, 'a1');
    expect(
      (section.activity.single as AgentChatActionGroupRow).streaming,
      isTrue,
    );
    expect(section.workedFor, isNull);
  });

  test('later prompts in a turn are steering and stay visible', () {
    final section = _section(
      AgentChatTimelineProjection.build(
        _thread(<Map<String, Object?>>[
          _item('u1', 'user_message', text: 'Start'),
          _item('a1', 'assistant_message', text: 'Working'),
          _item('u2', 'user_message', text: 'Also add tests'),
          _item('a2', 'assistant_message', text: 'Done'),
        ]),
      ),
    );
    expect(section.prompts.single.id, 'u1');
    expect(section.answers.map((item) => item.id), <String>['a1', 'u2', 'a2']);
  });

  test('plan checklists become progress; proposed plans are answers', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        _item('u1', 'user_message', text: 'Plan it'),
        _item(
          'p1',
          'plan',
          normalized: <String, Object?>{
            'planSteps': <Object?>[
              <String, Object?>{'step': 'Read code', 'status': 'completed'},
              <String, Object?>{'step': 'Write fix', 'status': 'inProgress'},
            ],
          },
        ),
        _item('p2', 'plan', text: '# Proposed plan\n- one'),
      ]),
    );
    final section = _section(projection);
    expect(section.planSteps?.id, 'p1');
    expect(section.answers.single.id, 'p2');
    expect(
      projection.activePlanSteps?.planSteps.last.status,
      AgentChatPlanStepStatus.inProgress,
    );
  });

  test('questions dock; approvals and forms are timeline entries', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(
        <Map<String, Object?>>[_item('n1', 'notice', turnId: null)],
        requests: <Map<String, Object?>>[
          <String, Object?>{
            'requestId': 'q1',
            'kind': 'tool_user_input',
            'createdAt': '2026-10-12T10:00:00Z',
            'questions': <Object?>[
              <String, Object?>{
                'id': 'scope',
                'header': 'Scope',
                'question': 'Which files?',
                'options': <Object?>[
                  <String, Object?>{
                    'label': 'All',
                    'description': 'Every file',
                  },
                ],
              },
            ],
          },
          <String, Object?>{
            'requestId': 'a1',
            'kind': 'file_change_approval',
            'createdAt': '2026-10-12T10:00:00Z',
          },
        ],
      ),
    );
    expect(projection.questions.single.id, 'q1');
    expect(projection.entries.map((entry) => entry.key), <String>[
      'item-n1',
      'request-a1',
    ]);
  });

  test('optimistic messages render until the runtime stamps them', () {
    final thread = _thread(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'Sent', clientMessageId: 'm1'),
    ]);
    final outgoing = <AgentChatOutgoingMessage>[
      AgentChatOutgoingMessage(
        clientMessageId: 'm1',
        text: 'Sent',
        createdAt: DateTime.utc(2026),
      ),
      AgentChatOutgoingMessage(
        clientMessageId: 'm2',
        text: 'Pending',
        createdAt: DateTime.utc(2026),
      ),
    ];
    final projection = AgentChatTimelineProjection.build(
      thread,
      outgoing: outgoing,
    );
    expect(
      projection.entries.whereType<AgentChatOutgoingEntry>().map(
        (entry) => entry.message.clientMessageId,
      ),
      <String>['m2'],
    );
  });

  test('unchanged turns reuse their section objects', () {
    final first = _thread(<Map<String, Object?>>[
      _item('u1', 'user_message', text: 'One'),
      _item('a1', 'assistant_message', text: 'Done', turnId: 'turn-1'),
      _item('u2', 'user_message', text: 'Two', turnId: 'turn-2'),
    ], activeTurnId: 'turn-2');
    final before = AgentChatTimelineProjection.build(first);
    final outcome = first.apply(
      AgentChatChange.fromJson(<String, Object?>{
        'chatId': 'chat-1',
        'cursor': 2,
        'delta': <String, Object?>{
          'items': <Object?>[
            _item(
              'a2',
              'assistant_message',
              text: 'Streaming',
              turnId: 'turn-2',
            ),
          ],
        },
      }),
    );
    final after = AgentChatTimelineProjection.build(
      (outcome as AgentChatApplied).thread,
      previous: before,
    );
    expect(
      identical(before.sectionFor('turn-1'), after.sectionFor('turn-1')),
      isTrue,
    );
    expect(
      identical(before.sectionFor('turn-2'), after.sectionFor('turn-2')),
      isFalse,
    );
  });

  test('automated input keeps its origin and stays out of prompt recall', () {
    final projection = AgentChatTimelineProjection.build(
      _thread(<Map<String, Object?>>[
        <String, Object?>{
          ..._item('w1', 'user_message', text: 'Tasks finished'),
          'normalized': <String, Object?>{
            'origin': <String, Object?>{
              'kind': 'orchestrationWake',
              'senderChatId': 'parent',
              'taskIds': <Object?>['t1', 't2'],
            },
          },
        },
        _item('u2', 'user_message', text: 'Mine', turnId: 'turn-2'),
      ]),
    );
    final wake = _sections(projection).first.prompts.single;
    expect(wake.isAutomatedInput, isTrue);
    expect(wake.origin!.kind, AgentChatItemOriginKind.orchestrationWake);
    expect(wake.origin!.taskIds, <String>['t1', 't2']);
    expect(projection.promptHistory, <String>['Mine']);
  });
}
