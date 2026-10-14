import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

AgentChatTask _task(
  String id,
  AgentChatTaskStatus status, {
  AgentChatTaskAttention attention = AgentChatTaskAttention.none,
}) => AgentChatTask(
  id: id,
  status: status,
  attention: attention,
  createdAt: _now.subtract(const Duration(minutes: 2)),
  updatedAt: _now.subtract(const Duration(minutes: 1)),
);

void main() {
  test('request dock prioritizes approvals then elicitations then questions without reordering decisions', () {
    final requests = <AgentChatRequest>[
      AgentChatRequest(
        id: 'question',
        kind: .toolUserInput,
        createdAt: _now.subtract(const Duration(minutes: 5)),
      ),
      AgentChatRequest(
        id: 'form',
        kind: .mcpElicitationApproval,
        createdAt: _now,
      ),
      AgentChatRequest(
        id: 'approval2',
        kind: .fileReadApproval,
        createdAt: _now,
      ),
      AgentChatRequest(
        id: 'approval1',
        kind: .execCommandApproval,
        createdAt: _now.subtract(const Duration(minutes: 1)),
        decisions: const <AgentChatApprovalDecision>[
          .decline,
          .acceptAlways,
          .cancel,
        ],
      ),
    ];
    final ordered = agentChatRequestDockOrder(requests);
    expect(ordered.map((request) => request.id), <String>[
      'approval1',
      'approval2',
      'form',
      'question',
    ]);
    expect(ordered.first.offeredDecisions, <AgentChatApprovalDecision>[
      .decline,
      .acceptAlways,
      .cancel,
    ]);
    expect(agentChatDecisionLabel(.cancel), 'Cancel Turn');
    expect(
      agentChatRequestTitle(
        AgentChatRequest(
          id: 'r',
          kind: .execCommandApproval,
          createdAt: _now,
          title: '  ',
        ),
      ),
      'Run Command?',
    );
    expect(
      agentChatRequestTitle(
        AgentChatRequest(
          id: 'r',
          kind: .toolUserInput,
          createdAt: _now,
          title: '  Your choice  ',
        ),
      ),
      'Your choice',
    );
  });

  test(
    'typing guard defers a request until idle and releases it on send or blur',
    () {
      expect(agentChatTypingIdle, const Duration(milliseconds: 1500));
      expect(
        agentChatRequestMayTakeFocus(
          now: _now,
          lastKeystroke: _now.subtract(const Duration(milliseconds: 1499)),
        ),
        isFalse,
      );
      expect(
        agentChatRequestMayTakeFocus(
          now: _now,
          lastKeystroke: _now.subtract(agentChatTypingIdle),
        ),
        isTrue,
      );
      expect(
        agentChatRequestMayTakeFocus(
          now: _now,
          lastKeystroke: _now,
          sentOrBlurred: true,
        ),
        isTrue,
      );
    },
  );

  test('task dock counts attention failures and settled tasks separately', () {
    final tasks = <AgentChatTask>[
      _task('done', .completed),
      _task('failed', .failed, attention: .failed),
      _task('run', .running),
      _task('input', .needsInput),
    ];
    final summary = AgentChatTaskDockSummary.of(tasks);
    expect(summary.open, 2);
    expect(summary.total, 4);
    expect(
      agentChatTaskDockSummaryLabel(summary),
      'Tasks · 1 running · 1 needs input · 1 failed · 1 done',
    );
    expect(agentChatTaskDockOrder(tasks).map((task) => task.id), <String>[
      'input',
      'failed',
      'run',
      'done',
    ]);
    expect(agentChatTaskElapsed(tasks.first, _now), const Duration(minutes: 1));
    expect(agentChatTaskElapsed(tasks[2], _now), const Duration(minutes: 2));
    expect(
      agentChatTaskElapsed(tasks[2], _now.subtract(const Duration(minutes: 3))),
      Duration.zero,
    );
  });

  test(
    'human delegated briefs say Task and preserve the creator as origin',
    () {
      const taskOrigin = AgentChatItemOrigin(
        kind: .chatMessage,
        taskIds: <String>['t'],
      );
      expect(agentChatOriginHeading(taskOrigin), 'Task');
      expect(agentChatOriginStartsExpanded(taskOrigin), isTrue);
      expect(
        agentChatTaskOriginLabel(_task('t', .running)),
        'Delegated by you',
      );
      expect(
        agentChatOriginHeading(
          const AgentChatItemOrigin(
            kind: .orchestrationWake,
            taskIds: <String>['one', 'two'],
          ),
        ),
        'Resumed after 2 delegated tasks finished',
      );
    },
  );

  test(
    'a human parent stays in drafts fingerprints and the outbound payload',
    () {
      const draft = AgentChatDelegateDraft(
        workspaceId: 'w',
        providerInstanceId: 'codex',
        parentChatId: 'parent',
        task: 'Run tests',
      );
      expect(draft.toInput('r').toJson()['parentChatId'], 'parent');
      expect(draft.copyWith(task: 'Run all tests').parentChatId, 'parent');
      expect(
        draft
            .copyWith(parentChatId: null)
            .toInput('r')
            .toJson()
            .containsKey('parentChatId'),
        isFalse,
      );
      expect(
        draft.copyWith(parentChatId: 'another').fingerprint,
        isNot(draft.fingerprint),
      );
    },
  );

  test('human parent wire stays guarded on old orchestration hosts', () async {
    final transport = AgentChatContractTransport(
      capabilities: <String>{AgentChatOrchestrationWire.capability},
    );
    addTearDown(transport.controller.close);
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    const input = AgentChatTaskMessageInput(
      requestId: 'r',
      chatId: 'child',
      parentChatId: 'parent',
      message: 'Follow up',
      expectReply: true,
    );
    expect(await repository.supportsPersonParent(), isFalse);
    await expectLater(
      repository.send(input),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(transport.requests, isEmpty);
    transport.capabilities.add(
      AgentChatOrchestrationWire.personParentCapability,
    );
    await repository.send(input);
    expect(transport.requests.single.$2['parentChatId'], 'parent');
  });
}
