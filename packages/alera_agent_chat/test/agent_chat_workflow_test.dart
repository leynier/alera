import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

const _chat = AgentChatRef(chatId: 'c', workspaceId: 'w');
final _start = DateTime.utc(2026, 10, 26, 9);

Map<String, Object?> _agent(
  int index,
  String state, {
  int? phase,
  String? phaseTitle,
  int? startedAfterSeconds,
  int? durationMs,
  String? agentId,
}) => <String, Object?>{
  'index': index,
  'label': 'agent:$index',
  'state': state,
  'phaseIndex': ?phase,
  'phaseTitle': ?phaseTitle,
  'agentId': ?agentId,
  if (startedAfterSeconds != null)
    'startedAt': _start
        .add(Duration(seconds: startedAfterSeconds))
        .millisecondsSinceEpoch,
  'durationMs': ?durationMs,
};

AgentChatItem _call(String status, Map<String, Object?> workflow) =>
    AgentChatItem.fromJson(<String, Object?>{
      'itemId': 'call',
      'turnId': 't',
      'type': 'dynamic_tool_call',
      'status': 'completed',
      'createdAt': _start.toIso8601String(),
      'updatedAt': _start.toIso8601String(),
      'title': 'Workflow',
      'normalized': <String, Object?>{
        'subagent': <String, Object?>{
          'status': status,
          'description': 'Run probe-wf',
          'taskType': 'local_workflow',
          'workflow': workflow,
        },
      },
    });

void main() {
  test('parses the runtime shape and drops what does not parse', () {
    final workflow = AgentChatWorkflow.fromJson(<String, Object?>{
      'name': 'probe-wf',
      'runHandles': <String, Object?>{
        'runId': 'wf_abc',
        'scriptPath': '/p/run.js',
      },
      'phases': <Object?>[
        <String, Object?>{'index': 1, 'title': ' Alpha '},
        <String, Object?>{'title': 'No index'},
        'nonsense',
      ],
      'agents': <Object?>[
        <String, Object?>{
          ..._agent(1, 'mystery', phase: 1, startedAfterSeconds: 0),
          'prompt': '  indented\n',
          'totalTokens': 12,
        },
        <String, Object?>{'index': -1, 'label': 'negative', 'state': 'queued'},
        <String, Object?>{'index': 2, 'state': 'queued'},
        <String, Object?>{
          'index': 3,
          'label': 'bad clock',
          'state': 'queued',
          'startedAt': 9e15,
        },
      ],
      'totalTokens': 1.5,
      'toolCalls': 4,
    })!;
    expect(workflow.name, 'probe-wf');
    expect(workflow.scriptPath, '/p/run.js');
    expect(workflow.phases.single.title, 'Alpha');
    expect(workflow.agents.map((agent) => agent.index), <int>[1, 3]);
    expect(workflow.agents.first.state, AgentChatWorkflowAgentState.running);
    expect(workflow.agents.first.prompt, '  indented\n');
    expect(workflow.agents.first.startedAt, _start);
    expect(workflow.agents.last.startedAt, isNull);
    expect(workflow.totalTokens, isNull);
    expect(workflow.toolCalls, 4);
    expect(AgentChatWorkflow.fromJson('nope'), isNull);
  });

  test('a workflow call is labelled by its script and grouped by phase', () {
    final call = _call('running', <String, Object?>{
      'name': 'probe-wf',
      'phases': <Object?>[
        <String, Object?>{'index': 0, 'title': 'Plan'},
        <String, Object?>{'index': 2, 'title': 'Review'},
      ],
      'agents': <Object?>[
        _agent(
          3,
          'running',
          phase: 1,
          phaseTitle: 'Guess',
          startedAfterSeconds: 5,
        ),
        _agent(
          1,
          'completed',
          phase: 0,
          startedAfterSeconds: 0,
          durationMs: 4000,
        ),
        _agent(2, 'failed', phase: 0, startedAfterSeconds: 1, durationMs: 9000),
        _agent(4, 'queued'),
      ],
      'totalTokens': 71141,
      'toolCalls': 3,
      'durationMs': 65000,
    });
    expect(call.subagentLabel, 'probe-wf');
    final group = call.workflowGroup!;
    expect(group.phases.map((phase) => phase.title), <String>[
      'Plan',
      'Guess',
      'Review',
    ]);
    final plan = group.phases[0];
    expect(plan.members.map((member) => member.index), <int>[1, 2]);
    expect(plan.state, AgentChatWorkflowPhaseState.done);
    expect(plan.statusLabel, 'failed');
    expect(plan.countLabel, '2/2 agents');
    expect(plan.elapsed(_start), const Duration(seconds: 10));
    final guess = group.phases[1];
    expect(guess.state, AgentChatWorkflowPhaseState.running);
    expect(guess.countLabel, '0/1 agent');
    expect(
      guess.elapsed(_start.add(const Duration(seconds: 20))),
      const Duration(seconds: 15),
    );
    expect(group.phases[2].state, AgentChatWorkflowPhaseState.pending);
    expect(group.phases[2].statusLabel, 'not started');
    expect(group.unphased.single.status, AgentChatWorkflowMemberStatus.queued);
    expect(group.lead, 'Kicked off 4 sub-agents');
    expect(group.summary, '2 working');
    expect(group.usage, '71k tokens · 3 tool calls · 1m 5s');
    expect(plan.members.first.statusLabel(_start), 'Completed in 4s');
    expect(
      guess.members.single.statusLabel(_start.add(const Duration(seconds: 7))),
      'Working 2s',
    );
  });

  test('a settled workflow settles the members it still lists as live', () {
    final agents = <Object?>[
      _agent(1, 'completed', phase: 0),
      _agent(2, 'running', phase: 0),
      _agent(3, 'queued', phase: 0),
    ];
    AgentChatWorkflowGroup group(String status) =>
        _call(status, <String, Object?>{'agents': agents}).workflowGroup!;
    final stopped = group('stopped');
    expect(
      stopped.members.map((member) => member.status),
      <AgentChatWorkflowMemberStatus>[
        AgentChatWorkflowMemberStatus.completed,
        AgentChatWorkflowMemberStatus.stopped,
        AgentChatWorkflowMemberStatus.stopped,
      ],
    );
    expect(stopped.lead, 'Ran 3 sub-agents');
    expect(stopped.summary, 'Workflow stopped');
    expect(stopped.phases.single.statusLabel, 'stopped');
    expect(group('failed').summary, 'Workflow failed');
    expect(group('completed').summary, 'Completed');
    expect(
      _call('completed', <String, Object?>{}).workflowGroup!.summary,
      'Status unavailable',
    );
    expect(
      _call('running', <String, Object?>{}).workflowGroup!.summary,
      'Working',
    );
  });

  test('lineage names a workflow and summarises its members', () {
    final relationships = AgentChatRelationships.build(
      chatId: 'c',
      chats: const <AgentChatSummary>[],
      items: <AgentChatItem>[
        _call('running', <String, Object?>{
          'name': 'probe-wf',
          'agents': <Object?>[_agent(1, 'running')],
        }),
      ],
    );
    final relation = relationships.active.single;
    expect(relation.title, 'probe-wf');
    expect(relation.kindLabel, 'Workflow');
    expect(relation.statusLabel, '1 working');
    expect(relation.workflow, isNotNull);
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
        repository.lifecycle.workflowScript(_chat, itemId: 'call'),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      await expectLater(
        repository.lifecycle.workflowAgent(
          _chat,
          itemId: 'call',
          agentIndex: 1,
        ),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      expect(transport.requests, isEmpty);
    });

    test('read the script and answers with exact payloads', () async {
      transport.capabilities.add(AgentChatWire.workflowsCapability);
      transport.responses[AgentChatWire.workflowScript] = <String, Object?>{
        'scriptPath': '/p/run.js',
        'contents': 'export const meta = {};',
        'truncated': true,
      };
      transport.responses[AgentChatWire.workflowAgent] = <String, Object?>{
        'answers': <Object?>['first', '  ', 7, 'second'],
      };
      final script = await repository.lifecycle.workflowScript(
        _chat,
        itemId: 'call',
      );
      expect(script.scriptPath, '/p/run.js');
      expect(script.contents, 'export const meta = {};');
      expect(script.truncated, isTrue);
      expect(
        await repository.lifecycle.workflowAgent(
          _chat,
          itemId: 'call',
          agentIndex: 2,
        ),
        <String>['first', 'second'],
      );
      expect(transport.requests.map((request) => request.$1), <String>[
        AgentChatWire.workflowScript,
        AgentChatWire.workflowAgent,
      ]);
      expect(transport.requests[0].$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'itemId': 'call',
      });
      expect(transport.requests[1].$2, <String, Object?>{
        'chatId': 'c',
        'workspaceId': 'w',
        'itemId': 'call',
        'agentIndex': 2,
      });
    });
  });
}
