part of 'agent_status_controller_test.dart';

AgentStatusEntry _snapshotEntry({
  String terminalSessionId = 'session-1',
  AgentStatusState state = AgentStatusState.working,
  required DateTime updatedAt,
}) {
  return AgentStatusEntry(
    terminalSessionId: terminalSessionId,
    workspaceId: 'workspace-1',
    tabId: 'tab-1',
    agentType: .codex,
    state: state,
    prompt: 'Run tests',
    updatedAt: updatedAt,
    stateStartedAt: updatedAt,
  );
}

void _registerAgentStatusSnapshotTests(ProviderContainer Function() container) {
  test('an identical snapshot does not replace the state', () {
    final controller = container().read(agentStatusControllerProvider.notifier);
    final at = DateTime.utc(2026, 5, 26, 2);

    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
    ]);
    final first = controller.state;
    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
    ]);

    // Identity, not just equality: a new map would rebuild every listener.
    expect(identical(controller.state, first), isTrue);
  });

  test('a stale snapshot does not resurrect a terminal that exited', () {
    // The host keeps a working presence for the life of the PTY when a
    // terminating hook never arrives, which is what left runs spinning
    // forever under orchestration load. The harness clock starts at 01:00,
    // so this snapshot predates the local resolution.
    final controller = container().read(agentStatusControllerProvider.notifier);
    final at = DateTime.utc(2026, 5, 26, 0, 30);
    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
    ]);

    controller.markTerminalExited(
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      exitCode: 0,
    );
    expect(controller.state['session-1']!.state, AgentStatusState.done);

    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
    ]);

    expect(controller.state['session-1']!.state, AgentStatusState.done);
  });

  test('a genuinely newer snapshot wins over the local resolution', () {
    final controller = container().read(agentStatusControllerProvider.notifier);
    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: .utc(2026, 5, 26, 0, 30)),
    ]);
    controller.markTerminalExited(
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      exitCode: 0,
    );

    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: .utc(2026, 5, 26, 9)),
    ]);

    expect(controller.state['session-1']!.state, AgentStatusState.working);
  });

  test('a snapshot does not un-clear a locally cleared terminal', () {
    final controller = container().read(agentStatusControllerProvider.notifier);
    final at = DateTime.utc(2026, 5, 26, 0, 30);
    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
    ]);

    controller.clearTerminal('session-1');
    expect(controller.state, isEmpty);

    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
    ]);

    expect(controller.state, isEmpty);
  });

  test('a clear is forgotten once the host stops reporting the session', () {
    final controller = container().read(agentStatusControllerProvider.notifier);
    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: .utc(2026, 5, 26, 0, 30)),
    ]);
    controller.clearTerminal('session-1');

    controller.replaceRuntimeSnapshot(const <AgentStatusEntry>[]);
    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: .utc(2026, 5, 26, 0, 30)),
    ]);

    expect(controller.state['session-1'], isNotNull);
  });

  test('unrelated sessions in the snapshot are kept', () {
    final controller = container().read(agentStatusControllerProvider.notifier);
    final at = DateTime.utc(2026, 5, 26, 0, 30);

    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
      _snapshotEntry(terminalSessionId: 'session-2', updatedAt: at),
    ]);
    controller.clearTerminal('session-1');
    controller.replaceRuntimeSnapshot(<AgentStatusEntry>[
      _snapshotEntry(updatedAt: at),
      _snapshotEntry(terminalSessionId: 'session-2', updatedAt: at),
    ]);

    expect(controller.state.keys, <String>['session-2']);
  });
}
