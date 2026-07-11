part of 'agent_status_controller_test.dart';

void _registerGrokAgentStatusControllerTests(
  ProviderContainer Function() readContainer,
) {
  test('clears stale status when a Grok Build session starts', () {
    final container = readContainer();
    final controller = container.read(agentStatusControllerProvider.notifier);
    controller.applyHookEvent(
      _event(
        agentType: AgentType.grok,
        hookEventName: 'UserPromptSubmit',
        payload: <String, Object?>{'prompt': 'old turn'},
      ),
    );
    expect(
      container.read(agentStatusControllerProvider),
      contains('session-1'),
    );

    controller.applyHookEvent(
      _event(
        agentType: AgentType.grok,
        hookEventName: 'SessionStart',
        payload: const <String, Object?>{},
      ),
    );

    expect(
      container.read(agentStatusControllerProvider),
      isNot(contains('session-1')),
    );
  });

  test('clears Grok Build status when the session ends', () {
    final container = readContainer();
    final controller = container.read(agentStatusControllerProvider.notifier);
    controller.applyHookEvent(
      _event(
        agentType: AgentType.grok,
        hookEventName: 'UserPromptSubmit',
        payload: <String, Object?>{'prompt': 'active turn'},
      ),
    );

    controller.applyHookEvent(
      _event(
        agentType: AgentType.grok,
        hookEventName: 'session_end',
        payload: const <String, Object?>{},
      ),
    );

    expect(
      container.read(agentStatusControllerProvider),
      isNot(contains('session-1')),
    );
  });
}
