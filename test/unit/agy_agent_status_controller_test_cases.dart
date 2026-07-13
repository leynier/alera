part of 'agent_status_controller_test.dart';

void _registerAgyAgentStatusControllerTests(
  ProviderContainer Function() readContainer,
) {
  test('normalizes AGY invocation and feedback tool states', () {
    final container = readContainer();
    final controller = container.read(agentStatusControllerProvider.notifier);

    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'PreInvocation',
        payload: <String, Object?>{'prompt': 'fix test'},
      ),
    );
    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'PreToolUse',
        payload: <String, Object?>{
          'toolCall': <String, Object?>{
            'name': 'ask_question',
            'args': <String, Object?>{'Prompt': 'Which file?'},
          },
        },
      ),
    );

    final entry = container.read(agentStatusControllerProvider)['session-1']!;
    expect(entry.state, AgentStatusState.waiting);
    expect(entry.prompt, 'fix test');
    expect(entry.toolName, 'ask_question');
    expect(entry.toolInput, 'Which file?');

    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'PostInvocation',
        payload: <String, Object?>{},
      ),
    );

    final postInvocationEntry = container.read(
      agentStatusControllerProvider,
    )['session-1']!;
    expect(postInvocationEntry.state, AgentStatusState.working);
    expect(postInvocationEntry.prompt, 'fix test');

    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'Stop',
        payload: <String, Object?>{
          'fullyIdle': false,
          'transcriptPath': '/tmp/agy-turn.jsonl',
        },
      ),
    );

    var stoppedEntry = container.read(
      agentStatusControllerProvider,
    )['session-1']!;
    expect(stoppedEntry.state, AgentStatusState.working);

    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'PostToolUse',
        payload: <String, Object?>{
          'transcriptPath': '/tmp/agy-turn.jsonl',
          'toolCall': <String, Object?>{
            'name': 'run_command',
            'args': <String, Object?>{'CommandLine': 'flutter test'},
          },
        },
      ),
    );
    expect(
      container.read(agentStatusControllerProvider)['session-1']!.toolName,
      'run_command',
    );

    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'Stop',
        payload: <String, Object?>{
          'fullyIdle': true,
          'transcriptPath': '/tmp/agy-turn.jsonl',
        },
      ),
    );
    stoppedEntry = container.read(agentStatusControllerProvider)['session-1']!;
    expect(stoppedEntry.state, AgentStatusState.done);
    expect(stoppedEntry.prompt, 'fix test');

    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'PostToolUse',
        payload: <String, Object?>{
          'transcriptPath': '/tmp/agy-turn.jsonl',
          'toolCall': <String, Object?>{
            'name': 'run_command',
            'args': <String, Object?>{'CommandLine': 'late command'},
          },
        },
      ),
    );
    expect(
      container.read(agentStatusControllerProvider)['session-1'],
      same(stoppedEntry),
    );

    controller.applyHookEvent(
      _event(
        agentType: AgentType.agy,
        hookEventName: 'PreInvocation',
        payload: <String, Object?>{'prompt': 'next turn'},
      ),
    );
    final nextTurn = container.read(
      agentStatusControllerProvider,
    )['session-1']!;
    expect(nextTurn.state, AgentStatusState.working);
    expect(nextTurn.prompt, 'next turn');
    expect(nextTurn.toolName, isNull);
  });
}
