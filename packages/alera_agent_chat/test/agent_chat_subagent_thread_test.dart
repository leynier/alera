import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

const _chat = AgentChatRef(chatId: 'c', workspaceId: 'w');

Map<String, Object?> _json(
  String id,
  String type, {
  String text = '',
  String? parent,
  Map<String, Object?> normalized = const <String, Object?>{},
}) => <String, Object?>{
  'itemId': id,
  'turnId': 'turn-1',
  'type': type,
  'status': 'completed',
  'createdAt': '2026-10-12T10:00:00Z',
  'updatedAt': '2026-10-12T10:00:00Z',
  'text': text,
  'normalized': <String, Object?>{...normalized, 'parentItemId': ?parent},
};

AgentChatItem _item(
  String id,
  String type, {
  String text = '',
  String? parent,
  Map<String, Object?> normalized = const <String, Object?>{},
}) => AgentChatItem.fromJson(
  _json(id, type, text: text, parent: parent, normalized: normalized),
);

AgentChatItem _call(
  String id,
  Map<String, Object?> subagent, {
  String? parent,
  String description = 'Count files',
}) => _item(
  id,
  'collab_agent_tool_call',
  parent: parent,
  normalized: <String, Object?>{
    'subagent': <String, Object?>{'description': description, ...subagent},
    'input': <String, Object?>{'prompt': 'Count every file'},
  },
);

void main() {
  test('descendants follow nested calls and continuation rows', () {
    final items = <AgentChatItem>[
      _call('call', <String, Object?>{'status': 'running'}),
      _item('a', 'assistant_message', text: 'one', parent: 'call'),
      _item('other', 'assistant_message', text: 'main'),
      _call('nested', <String, Object?>{'status': 'running'}, parent: 'call'),
      _item('b', 'command_execution', parent: 'nested'),
      _item('b:segment:text:1', 'command_execution'),
      _item('stranger', 'command_execution', parent: 'elsewhere'),
    ];
    expect(
      agentChatSubagentDescendants(items, 'call').map((item) => item.id),
      <String>['a', 'nested', 'b', 'b:segment:text:1'],
    );
  });

  test('a sub-agent timeline folds its own work and nests its sub-agents', () {
    final call = _call('call', <String, Object?>{'status': 'completed'});
    final timeline = AgentChatSubagentTimeline.build(call, <AgentChatItem>[
      _item('a', 'assistant_message', text: 'Looking', parent: 'call'),
      _call(
        'nested',
        <String, Object?>{'status': 'running'},
        parent: 'call',
        description: 'Dig',
      ),
      _item('b', 'command_execution', parent: 'nested'),
    ]);
    expect(timeline.label, 'Count files');
    expect(timeline.prompt, 'Count every file');
    expect(timeline.rows.first, isA<AgentChatItemRow>());
    final nested = timeline.rows.last as AgentChatSubagentRow;
    expect(nested.label, 'Dig');
    expect(nested.childCount, 1);
  });

  test('the status label counts live and settled time', () {
    final now = DateTime.utc(2026, 10, 12, 10, 1, 5);
    AgentChatItem call(Map<String, Object?> subagent) => _call('c', subagent);
    expect(
      agentChatSubagentStatusLabel(
        call(<String, Object?>{
          'status': 'running',
          'startedAt': '2026-10-12T10:00:00Z',
        }),
        now,
      ),
      'Working 1m 5s',
    );
    expect(
      agentChatSubagentStatusLabel(
        call(<String, Object?>{
          'status': 'completed',
          'startedAt': '2026-10-12T10:00:00Z',
          'completedAt': '2026-10-12T10:00:42Z',
        }),
        now,
      ),
      'Completed in 42s',
    );
    expect(
      agentChatSubagentStatusLabel(
        call(<String, Object?>{'status': 'stopped'}),
        now,
      ),
      'Stopped',
    );
    expect(
      agentChatSubagentStatusLabel(
        call(<String, Object?>{'status': 'running'}),
        now,
      ),
      'Working',
    );
  });

  test('model and effort come from the runtime, else the call input', () {
    final reported = _call('c', <String, Object?>{
      'status': 'running',
      'model': 'gpt-6-luna',
      'reasoningEffort': 'high',
    });
    expect(reported.subagentModel, 'gpt-6-luna');
    expect(reported.subagentReasoningEffort, 'high');
    final asked = _item(
      'task',
      'dynamic_tool_call',
      normalized: <String, Object?>{
        'toolName': 'Task',
        'input': <String, Object?>{'model': 'haiku'},
      },
    );
    expect(asked.subagentModel, 'haiku');
  });

  group('runtime verbs', () {
    late AgentChatContractTransport transport;
    late RuntimeAgentChatRepository repository;
    setUp(() {
      transport = AgentChatContractTransport();
      repository = RuntimeAgentChatRepository(transport);
    });
    tearDown(() => transport.controller.close());

    test('are capability guarded', () async {
      await expectLater(
        repository.lifecycle.subagent(_chat, itemId: 'call'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.stopSubagent(
          _chat,
          requestId: 'r',
          itemId: 'call',
        ),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.mergeBack(_chat, requestId: 'r'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      expect(transport.requests, isEmpty);
    });

    test('read, stop and merge back with exact payloads', () async {
      transport.capabilities.addAll(<String>{
        AgentChatWire.subagentThreadsCapability,
        AgentChatWire.mergeBackCapability,
      });
      transport.responses[AgentChatWire.subagent] = <String, Object?>{
        'call': _json(
          'call',
          'collab_agent_tool_call',
          normalized: <String, Object?>{
            'subagent': <String, Object?>{'status': 'running'},
          },
        ),
        'items': <Object?>[
          _json('a', 'assistant_message', text: 'hi', parent: 'call'),
        ],
        'truncated': true,
      };
      transport.responses[AgentChatWire.mergeBack] = <String, Object?>{
        'chatId': 'source',
        'itemId': 'notice',
        'status': 'pending',
      };
      final transcript = await repository.lifecycle.subagent(
        _chat,
        itemId: 'call',
      );
      expect(transcript.call.id, 'call');
      expect(transcript.items.single.text, 'hi');
      expect(transcript.truncated, isTrue);
      await repository.lifecycle.stopSubagent(
        _chat,
        requestId: 'stop-1',
        itemId: 'call',
      );
      expect(
        await repository.lifecycle.mergeBack(_chat, requestId: 'merge-1'),
        'source',
      );
      expect(transport.requests.map((request) => request.$1), <String>[
        AgentChatWire.subagent,
        AgentChatWire.stopSubagent,
        AgentChatWire.mergeBack,
      ]);
      expect(transport.requests[0].$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'itemId': 'call',
      });
      expect(transport.requests[1].$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'requestId': 'stop-1',
        'itemId': 'call',
      });
      expect(transport.requests[2].$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'requestId': 'merge-1',
      });
    });
  });
}
