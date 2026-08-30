part of 'agent_hook_event_normalizer_test.dart';

void _registerGrokAgentHookEventNormalizerTests() {
  test('normalizes Grok Build lifecycle and notification states', () {
    final prompt = normalizeAgentHookEvent(
      _event(
        agentType: .grok,
        hookEventName: 'user_prompt_submit',
        payload: const <String, Object?>{
          'prompt': '<user_query>\nShip the feature\n</user_query>',
        },
      ),
    );
    expect(prompt?.state, AgentStatusState.working);
    expect(prompt?.prompt, 'Ship the feature');

    final previous = AgentStatusEntry(
      terminalSessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      agentType: .grok,
      state: .working,
      prompt: prompt!.prompt,
      updatedAt: .utc(2026, 7, 10),
      stateStartedAt: .utc(2026, 7, 10),
    );
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .grok,
          hookEventName: 'Notification',
          payload: const <String, Object?>{
            'notificationType': 'permission_prompt',
            'message': 'Tool permission requested',
            'level': 'info',
          },
        ),
        previous: previous,
      ),
      isNull,
    );

    final waiting = normalizeAgentHookEvent(
      _event(
        agentType: .grok,
        hookEventName: 'Notification',
        payload: const <String, Object?>{
          'message': 'Grok needs your feedback to proceed',
        },
      ),
      previous: previous,
    );
    expect(waiting?.state, AgentStatusState.waiting);
    expect(waiting?.prompt, 'Ship the feature');

    final idle = normalizeAgentHookEvent(
      _event(
        agentType: .grok,
        hookEventName: 'notification',
        payload: const <String, Object?>{'message': 'Type your message'},
      ),
      previous: previous,
    );
    expect(idle?.state, AgentStatusState.done);
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .grok,
          hookEventName: 'Notification',
          payload: const <String, Object?>{'message': 'Ask a side question'},
        ),
        previous: previous,
      )?.state,
      AgentStatusState.done,
    );
    for (final eventName in const <String>['stop_failure', 'session_end']) {
      expect(
        normalizeAgentHookEvent(
          _event(
            agentType: .grok,
            hookEventName: eventName,
            payload: const <String, Object?>{},
          ),
          previous: previous,
        )?.state,
        AgentStatusState.done,
      );
    }
  });
}
