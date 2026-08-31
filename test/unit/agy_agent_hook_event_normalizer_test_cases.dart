part of 'agent_hook_event_normalizer_test.dart';

void _registerAgyAgentHookEventNormalizerTests() {
  test('keeps AGY working until Stop reports fully idle', () {
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .agy,
          hookEventName: 'Stop',
          payload: const <String, Object?>{'fullyIdle': false},
        ),
      )?.state,
      AgentStatusState.working,
    );
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .agy,
          hookEventName: 'Stop',
          payload: const <String, Object?>{'fully_idle': false},
        ),
      )?.state,
      AgentStatusState.working,
    );
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .agy,
          hookEventName: 'Stop',
          payload: const <String, Object?>{'fullyIdle': true},
        ),
      )?.state,
      AgentStatusState.done,
    );
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .agy,
          hookEventName: 'Stop',
          payload: const <String, Object?>{},
        ),
      )?.state,
      AgentStatusState.done,
    );
  });
}
