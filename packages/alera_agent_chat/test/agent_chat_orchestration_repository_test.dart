import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

typedef _Handler = FutureOr<Map<String, Object?>> Function(
  Map<String, Object?> payload,
);

final class _FakeTransport implements AgentChatTransport {
  _FakeTransport({this.capable = true});

  bool capable;
  final List<(String, Map<String, Object?>, Duration?)> requests =
      <(String, Map<String, Object?>, Duration?)>[];
  final Map<String, _Handler> handlers = <String, _Handler>{};
  final StreamController<AgentChatTransportEvent> controller =
      StreamController<AgentChatTransportEvent>.broadcast(sync: true);

  @override
  Stream<AgentChatTransportEvent> get events => controller.stream;

  @override
  Future<bool> supportsCapability(String capability) async =>
      capable && capability == AgentChatOrchestrationWire.capability;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload, timeout));
    final handler = handlers[type];
    return handler == null ? const <String, Object?>{} : await handler(payload);
  }

  void emit(String name, [Map<String, Object?> payload = const {}]) =>
      controller.add(AgentChatTransportEvent(name, payload));

  Iterable<String> get verbs => requests.map((request) => request.$1);
}

Map<String, Object?> _task(String id, {String status = 'running'}) =>
    <String, Object?>{
      'taskId': id,
      'status': status,
      'createdAt': '2026-10-12T10:00:00Z',
      'updatedAt': '2026-10-12T10:00:00Z',
    };

Map<String, Object?> _page(List<String> ids) => <String, Object?>{
  'tasks': <Object?>[for (final id in ids) _task(id)],
};

void main() {
  test('fails closed without the capability and sends nothing', () async {
    final transport = _FakeTransport(capable: false);
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    expect(await repository.supported(), isFalse);
    await expectLater(
      repository.tasks(const AgentChatTaskQuery()),
      throwsA(isA<AgentChatOrchestrationUpdateRequired>()),
    );
    await expectLater(
      repository.cancel('task-1', requestId: 'r-1'),
      throwsA(isA<AgentChatOrchestrationUpdateRequired>()),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'delegate sends an explicit target, an async mode and the agent',
    () async {
      final transport = _FakeTransport()
        ..handlers[AgentChatOrchestrationWire.delegate] = (_) =>
            <String, Object?>{
              'taskId': 'task-1',
              'status': 'preparing',
              'task': _task('task-1', status: 'preparing'),
            };
      final repository = RuntimeAgentChatOrchestrationRepository(transport);
      final result = await repository.delegate(
        const AgentChatDelegateInput(
          requestId: 'request-1',
          task: 'Fix the flaky test',
          title: 'Flaky test',
          target: AgentChatTaskNewWorkspaceTarget(
            projectId: 'project-1',
            hostId: 'ssh-1',
            mode: AgentChatWorkspaceMode.worktree,
            branch: 'fix/flaky',
          ),
          agent: AgentChatTaskAgent(
            providerInstanceId: 'codex',
            model: 'gpt-5',
          ),
          runtimeMode: AgentChatRuntimeMode.autoAcceptEdits,
        ),
      );
      expect(result.taskId, 'task-1');
      expect(result.status, AgentChatTaskStatus.preparing);
      final (verb, payload, timeout) = transport.requests.single;
      expect(verb, AgentChatOrchestrationWire.delegate);
      expect(timeout, isNotNull);
      expect(payload, <String, Object?>{
        'requestId': 'request-1',
        'task': 'Fix the flaky test',
        'mode': 'async',
        'target': <String, Object?>{
          'newWorkspace': <String, Object?>{
            'projectId': 'project-1',
            'hostId': 'ssh-1',
            'mode': 'worktree',
            'branch': 'fix/flaky',
            'setup': 'inline',
          },
        },
        'title': 'Flaky test',
        'agent': <String, Object?>{
          'providerInstanceId': 'codex',
          'model': 'gpt-5',
        },
        'runtimeMode': 'auto-accept-edits',
      });
    },
  );

  test('task list filters go out with their wire names', () async {
    final transport = _FakeTransport()
      ..handlers[AgentChatOrchestrationWire.tasksList] = (_) =>
          _page(<String>['task-1']);
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    await repository.tasks(
      const AgentChatTaskQuery(
        statuses: <AgentChatTaskStatus>{
          AgentChatTaskStatus.failed,
          AgentChatTaskStatus.needsInput,
        },
        attention: true,
        parentChatId: 'chat-1',
        projectId: 'project-1',
        limit: 10,
      ),
      cursor: 'cursor-2',
    );
    expect(transport.requests.single.$2, <String, Object?>{
      'statuses': <String>['needs_input', 'failed'],
      'attention': true,
      'parentChatId': 'chat-1',
      'projectId': 'project-1',
      'limit': 10,
      'cursor': 'cursor-2',
    });
  });

  test('queries compare by value so a watched list keeps its identity', () {
    const a = AgentChatTaskQuery(
      statuses: <AgentChatTaskStatus>{
        AgentChatTaskStatus.failed,
        AgentChatTaskStatus.running,
      },
      workspaceId: 'ws-1',
    );
    const b = AgentChatTaskQuery(
      statuses: <AgentChatTaskStatus>{
        AgentChatTaskStatus.running,
        AgentChatTaskStatus.failed,
      },
      workspaceId: 'ws-1',
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const AgentChatTaskQuery(workspaceId: 'ws-1'), isFalse);
  });

  test('a wait is bounded by the runtime maximum and its timeout', () async {
    final transport = _FakeTransport()
      ..handlers[AgentChatOrchestrationWire.wait] = (_) => <String, Object?>{
        'tasks': <Object?>[_task('task-1')],
        'timedOut': true,
      };
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    final result = await repository.wait(<String>['task-1'], waitSeconds: 300);
    expect(result.timedOut, isTrue);
    await repository.wait(
      <String>['task-1', 'task-2'],
      waitSeconds: 0,
      until: AgentChatTaskWaitUntil.any,
    );
    final (_, first, firstTimeout) = transport.requests[0];
    expect(first, <String, Object?>{
      'taskIds': <String>['task-1'],
      'waitSeconds': 50,
    });
    expect(firstTimeout, const Duration(seconds: 60));
    final (_, second, _) = transport.requests[1];
    expect(second, <String, Object?>{
      'taskIds': <String>['task-1', 'task-2'],
      'waitSeconds': 1,
      'until': 'any',
    });
  });

  test(
    'mutations carry their request ids and read only acknowledges on ask',
    () async {
      final transport = _FakeTransport();
      transport.handlers[AgentChatOrchestrationWire.cancel] = (_) =>
          <String, Object?>{
            'task': _task('task-1', status: 'cancel_requested'),
            'cancelledTaskIds': <String>['task-1', 'task-2'],
          };
      transport.handlers[AgentChatOrchestrationWire.task] = (_) =>
          <String, Object?>{'task': _task('task-1', status: 'completed')};
      transport.handlers[AgentChatOrchestrationWire.configure] = (_) =>
          <String, Object?>{
            'snapshot': <String, Object?>{
              'chatId': 'chat-1',
              'workspaceId': 'ws-1',
              'cursor': 1,
            },
          };
      final repository = RuntimeAgentChatOrchestrationRepository(transport);
      final cancelled = await repository.cancel(
        'task-1',
        requestId: 'r-cancel',
      );
      expect(cancelled.status, AgentChatTaskStatus.cancelRequested);
      await repository.task('task-1');
      await repository.task('task-1', acknowledge: true);
      await repository.interrupt('chat-1', requestId: 'r-stop');
      await repository.respond(
        chatId: 'chat-1',
        requestId: 'r-answer',
        runtimeRequestId: 'runtime-request-1',
        response: const AgentChatApprovalResponse(
          AgentChatApprovalDecision.accept,
        ),
      );
      await repository.configure(
        'chat-1',
        requestId: 'r-config',
        configuration: const AgentChatConfiguration(
          provider: 'claudeAgent',
          providerInstanceId: 'claudeAgent',
          model: 'opus',
        ),
      );
      final payloads = <String, List<Map<String, Object?>>>{};
      for (final (verb, payload, _) in transport.requests) {
        payloads.putIfAbsent(verb, () => <Map<String, Object?>>[]).add(payload);
      }
      expect(
        payloads[AgentChatOrchestrationWire.cancel]!.single,
        <String, Object?>{'requestId': 'r-cancel', 'taskId': 'task-1'},
      );
      expect(payloads[AgentChatOrchestrationWire.task], <Map<String, Object?>>[
        <String, Object?>{'taskId': 'task-1'},
        <String, Object?>{'taskId': 'task-1', 'acknowledge': true},
      ]);
      expect(
        payloads[AgentChatOrchestrationWire.interrupt]!.single,
        <String, Object?>{'requestId': 'r-stop', 'chatId': 'chat-1'},
      );
      expect(
        payloads[AgentChatOrchestrationWire.respond]!.single,
        <String, Object?>{
          'requestId': 'r-answer',
          'chatId': 'chat-1',
          'runtimeRequestId': 'runtime-request-1',
          'response': <String, Object?>{
            'type': 'approval',
            'decision': 'accept',
          },
        },
      );
      expect(
        payloads[AgentChatOrchestrationWire.configure]!.single,
        <String, Object?>{
          'requestId': 'r-config',
          'chatId': 'chat-1',
          'providerInstanceId': 'claudeAgent',
          'model': 'opus',
        },
      );
    },
  );

  test(
    'capabilities keep orchestration flags across another catalog',
    () async {
      final transport = _FakeTransport()
        ..handlers[AgentChatOrchestrationWire.capabilities] = (_) =>
            <String, Object?>{
              'maxWaitSeconds': 50,
              'ceilingRuntimeModes': <String>['approval-required', 'auto'],
              'providers': <Object?>[
                <String, Object?>{
                  'providerInstanceId': 'codex',
                  'provider': 'codex',
                  'label': 'Codex',
                  'orchestration': <String, Object?>{'supported': true},
                },
                <String, Object?>{
                  'providerInstanceId': 'pi',
                  'provider': 'pi',
                  'label': 'Pi',
                  'orchestration': <String, Object?>{
                    'supported': false,
                    'reason': 'No MCP boundary.',
                  },
                },
              ],
            };
      final repository = RuntimeAgentChatOrchestrationRepository(transport);
      final capabilities = await repository.capabilities();
      expect(transport.requests.single.$2, isEmpty);
      expect(capabilities.providers.map((provider) => provider.id), <String>[
        'codex',
        'pi',
      ]);
      expect(capabilities.supportFor('codex')?.supported, isTrue);
      expect(capabilities.supportFor('pi')?.reason, 'No MCP boundary.');
      expect(capabilities.ceilingRuntimeModes, <AgentChatRuntimeMode>[
        AgentChatRuntimeMode.approvalRequired,
        AgentChatRuntimeMode.auto,
      ]);
      final remote = capabilities.withProviders(
        const <AgentChatProviderInstance>[
          AgentChatProviderInstance(id: 'pi', provider: 'pi', label: 'Pi'),
        ],
      );
      expect(remote.providers.single.id, 'pi');
      expect(remote.supportFor('pi')?.supported, isFalse);
    },
  );

  test('requests skip rows the client cannot answer', () async {
    final transport = _FakeTransport()
      ..handlers[AgentChatOrchestrationWire.requests] = (_) =>
          <String, Object?>{
            'requests': <Object?>[
              <String, Object?>{
                'chatId': 'chat-2',
                'taskId': 'task-2',
                'request': <String, Object?>{
                  'requestId': 'req-1',
                  'kind': 'command_execution_approval',
                  'command': 'rm -rf build',
                  'decisions': <String>['accept', 'decline'],
                },
              },
              <String, Object?>{'taskId': 'task-3'},
            ],
          };
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    final requests = await repository.requests(taskId: 'task-2');
    expect(transport.requests.single.$2, <String, Object?>{'taskId': 'task-2'});
    expect(requests.single.chatId, 'chat-2');
    expect(requests.single.request.isApproval, isTrue);
    expect(requests.single.request.command, 'rm -rf build');
  });

  test('error messages map runtime codes in either spelling', () {
    expect(
      agentChatOrchestrationErrorMessage(
        const AgentChatRequestException(message: '', code: 'task_not_found'),
      ),
      'This task no longer exists on the runtime.',
    );
    expect(
      agentChatOrchestrationErrorMessage(
        const AgentChatRequestException(message: '', code: 'taskNotFound'),
      ),
      'This task no longer exists on the runtime.',
    );
    expect(
      agentChatOrchestrationErrorMessage(
        const AgentChatRequestException(
          message: 'The target runs above your mode.',
          code: 'mode_ceiling',
        ),
      ),
      'The target runs above your mode.',
    );
    expect(
      agentChatOrchestrationErrorMessage(
        const AgentChatOrchestrationUpdateRequired(),
      ),
      contains('Update it to continue'),
    );
    expect(
      agentChatOrchestrationErrorMessage(StateError('boom')),
      'The chat task action failed.',
    );
  });
}
