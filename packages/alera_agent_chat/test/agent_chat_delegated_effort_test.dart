import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

void main() {
  test('default effort omits options and explicit effort preserves the native token', () {
    expect(
      const AgentChatTaskAgent(providerInstanceId: 'codex').toJson(),
      <String, Object?>{'providerInstanceId': 'codex'},
    );
    expect(
      const AgentChatTaskAgent(
        providerInstanceId: 'codex',
        reasoningEffort: ' ',
      ).toJson().containsKey('options'),
      isFalse,
    );
    expect(
      const AgentChatTaskAgent(reasoningEffort: 'xhigh').toJson(),
      <String, Object?>{
        'options': <String, Object?>{'reasoningEffort': 'xhigh'},
      },
    );
  });

  test('new-chat draft keeps effort in the request and retry fingerprint', () {
    const draft = AgentChatDelegateDraft(
      workspaceId: 'w',
      providerInstanceId: 'codex',
      task: 'Investigate',
      reasoningEffort: 'high',
    );
    expect(draft.toInput('r').agent?.reasoningEffort, 'high');
    expect(draft.copyWith(title: 'Review').reasoningEffort, 'high');
    expect(
      draft.copyWith(reasoningEffort: 'low').fingerprint,
      isNot(draft.fingerprint),
    );
    expect(
      draft
          .copyWith(reasoningEffort: null)
          .toInput('r')
          .agent!
          .toJson()
          .containsKey('options'),
      isFalse,
    );
  });

  test(
    'an existing-chat effort override does not replace its provider or model',
    () {
      const draft = AgentChatDelegateDraft(
        targetKind: .chat,
        chatId: 'target',
        providerInstanceId: 'ignored',
        model: 'ignored',
        task: 'Investigate',
        reasoningEffort: 'high',
      );
      expect(draft.toInput('r').agent!.toJson(), <String, Object?>{
        'options': <String, Object?>{'reasoningEffort': 'high'},
      });
      expect(draft.copyWith(reasoningEffort: null).toInput('r').agent, isNull);
    },
  );

  test(
    'delegation requires the dedicated orchestration effort capability',
    () async {
      final transport = AgentChatContractTransport(
        capabilities: <String>{
          AgentChatOrchestrationWire.capability,
          AgentChatWire.effortCapability,
        },
      );
      addTearDown(transport.controller.close);
      final repository = RuntimeAgentChatOrchestrationRepository(transport);
      const input = AgentChatDelegateInput(
        requestId: 'r',
        task: 'Investigate',
        target: AgentChatTaskChatTarget('target'),
        agent: AgentChatTaskAgent(reasoningEffort: 'high'),
      );
      expect(await repository.supportsEffort(), isFalse);
      await expectLater(
        repository.delegate(input),
        throwsA(isA<AgentChatCapabilityRequired>()),
      );
      expect(transport.requests, isEmpty);
      transport.capabilities.add(AgentChatOrchestrationWire.effortCapability);
      transport.responses[AgentChatOrchestrationWire.delegate] =
          <String, Object?>{'taskId': 'task', 'status': 'preparing'};
      await repository.delegate(input);
      expect(transport.requests.single.$2['agent'], <String, Object?>{
        'options': <String, Object?>{'reasoningEffort': 'high'},
      });
    },
  );

  test(
    'old orchestration hosts still accept default-effort delegations',
    () async {
      final transport = AgentChatContractTransport(
        capabilities: <String>{AgentChatOrchestrationWire.capability},
      );
      addTearDown(transport.controller.close);
      final repository = RuntimeAgentChatOrchestrationRepository(transport);
      transport.responses[AgentChatOrchestrationWire.delegate] =
          <String, Object?>{'taskId': 'task', 'status': 'preparing'};
      await repository.delegate(
        const AgentChatDelegateInput(
          requestId: 'r',
          task: 'Investigate',
          target: AgentChatTaskWorkspaceTarget('w'),
          agent: AgentChatTaskAgent(providerInstanceId: 'codex'),
        ),
      );
      final agent = transport.requests.single.$2['agent'] as Map;
      expect(agent.containsKey('options'), isFalse);
    },
  );

  test('orchestration configure preserves omission and reset under the effort capability', () async {
    final transport = AgentChatContractTransport(
      capabilities: <String>{AgentChatOrchestrationWire.capability},
    );
    addTearDown(transport.controller.close);
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    await expectLater(
      repository.configure(
        'c',
        requestId: 'reset',
        configuration: const AgentChatConfiguration(resetReasoningEffort: true),
      ),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
    transport.responses[AgentChatOrchestrationWire.configure] =
        <String, Object?>{'snapshot': agentChatContractSnapshot()};
    await repository.configure(
      'c',
      requestId: 'model',
      configuration: const AgentChatConfiguration(resetModel: true),
    );
    expect(
      transport.requests.single.$2.containsKey('reasoningEffort'),
      isFalse,
    );
    transport.capabilities.add(AgentChatOrchestrationWire.effortCapability);
    await repository.configure(
      'c',
      requestId: 'reset',
      configuration: const AgentChatConfiguration(resetReasoningEffort: true),
    );
    expect(transport.requests.last.$2.containsKey('reasoningEffort'), isTrue);
    expect(transport.requests.last.$2['reasoningEffort'], isNull);
  });
}
