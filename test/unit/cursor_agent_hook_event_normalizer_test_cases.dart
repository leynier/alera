part of 'agent_hook_event_normalizer_test.dart';

void _registerCursorAgentHookEventNormalizerTests() {
  test('keeps Cursor shell and MCP execution as working', () {
    final shell = normalizeAgentHookEvent(
      _event(
        agentType: .cursor,
        hookEventName: 'beforeShellExecution',
        payload: const <String, Object?>{'command': 'sleep 30'},
      ),
    );
    expect(shell?.state, AgentStatusState.working);
    expect(shell?.toolName, 'Shell');
    expect(shell?.toolInput, 'sleep 30');

    final mcp = normalizeAgentHookEvent(
      _event(
        agentType: .cursor,
        hookEventName: 'beforeMCPExecution',
        payload: const <String, Object?>{'tool_name': 'Browser'},
      ),
    );
    expect(mcp?.state, AgentStatusState.working);
    expect(mcp?.toolName, 'Browser');

    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'afterShellExecution',
          payload: const <String, Object?>{'command': 'sleep 30'},
        ),
      )?.state,
      AgentStatusState.working,
    );
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'afterMCPExecution',
          payload: const <String, Object?>{'tool_name': 'Browser'},
        ),
      )?.state,
      AgentStatusState.working,
    );
  });

  test('maps Cursor AskQuestion preToolUse to waiting', () {
    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'preToolUse',
          payload: const <String, Object?>{
            'tool_name': 'AskQuestion',
            'tool_input': <String, Object?>{'title': 'Which path?'},
          },
        ),
      )?.state,
      AgentStatusState.waiting,
    );
  });

  test('extracts Cursor shell, MCP, and tool response snapshots', () {
    final shell = normalizeAgentHookEvent(
      _event(
        agentType: .cursor,
        hookEventName: 'beforeShellExecution',
        payload: const <String, Object?>{'command': 'flutter test'},
      ),
    );
    expect(shell?.state, AgentStatusState.working);
    expect(shell?.toolName, 'Shell');
    expect(shell?.toolInput, 'flutter test');

    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'beforeMCPExecution',
          payload: const <String, Object?>{
            'toolName': 'Browser',
            'url': 'https://example.test',
          },
        ),
      )?.toolInput,
      'https://example.test',
    );

    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'postToolUse',
          payload: const <String, Object?>{'output': 'tool done'},
        ),
      )?.lastAssistantMessage,
      'tool done',
    );

    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'postToolUseFailure',
          payload: const <String, Object?>{'error': 'tool failed'},
        ),
      )?.lastAssistantMessage,
      'tool failed',
    );

    expect(
      normalizeAgentHookEvent(
        _event(
          agentType: .cursor,
          hookEventName: 'preToolUse',
          payload: const <String, Object?>{
            'toolName': 'JsonFallback',
            'input': 42,
          },
        ),
      )?.toolInput,
      '42',
    );
  });
}
