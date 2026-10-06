part of 'workbench_controller_test.dart';

/// Exits whose handling races a wake, a restart, or the rest of the sleep.
void _registerWorkbenchControllerSleepExitRaceTests() {
  test(
    'a sibling that woke the workspace wins over a late settlement',
    () async {
      final (workspace, terminal) = await _selectWithTerminal();
      final second = await _openSecondTerminal(workspace, terminal);
      _handleFor(workspace, second).terminalSessionId = 'second-session';
      final gate = Completer<void>();
      _harness.workbenchRepository
        ..sleptTabs = <String, List<String>>{
          workspace.id: <String>[terminal.id, second.id],
        }
        ..sleptTabsGate = gate;

      _harness.terminalRuntime.emitExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspace.id,
          tabId: second.id,
          exitCode: -1,
        ),
      );
      await _flush();
      // Reopening the first terminal wakes the workspace before the answer.
      final awake = _handleFor(workspace, terminal);
      await awake.ensureStarted();
      gate.complete();
      await _flushUntil(
        () =>
            _harness.hookReceiver.clearedSessionIds.contains('second-session'),
      );

      expect(_controller.state.activeWorkspace?.id, workspace.id);
      expect(
        _controller.state.sleptTabIdsByWorkspaceId[workspace.id],
        isNot(contains(terminal.id)),
      );
      // The exited handle stays mounted rather than being disposed under it.
      expect(_harness.terminalRuntime.releasedTabIds, isEmpty);
      expect(_controller.state.tabsFor(workspace.id), hasLength(2));
    },
  );

  test(
    'a terminal opened during the lookup keeps the workspace open',
    () async {
      final (workspace, terminal) = await _selectWithTerminal();
      _handleFor(workspace, terminal).terminalSessionId = 'slept-session';
      final gate = Completer<void>();
      _harness.workbenchRepository
        ..sleptTabs = <String, List<String>>{
          workspace.id: <String>[terminal.id],
        }
        ..sleptTabsGate = gate;

      _harness.terminalRuntime.emitExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspace.id,
          tabId: terminal.id,
          exitCode: -1,
        ),
      );
      await _flush();
      final fresh = await _openSecondTerminal(workspace, terminal);
      await _handleFor(workspace, fresh).ensureStarted();
      gate.complete();
      await _flushUntil(
        () => _harness.hookReceiver.clearedSessionIds.contains('slept-session'),
      );

      expect(_controller.state.activeWorkspace?.id, workspace.id);
      expect(_harness.terminalRuntime.releasedTabIds, isEmpty);
      expect(_harness.terminalRuntime.peekSession(fresh.id), isNotNull);
    },
  );

  test('a sleep exit answered after a sibling woke keeps its tab', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final second = await _openSecondTerminal(workspace, terminal);
    _handleFor(workspace, second).terminalSessionId = 'second-session';
    // The sibling woke the workspace, which cleared the host's slept list.
    await _handleFor(workspace, terminal).ensureStarted();

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: second.id,
        exitCode: -1,
        cause: .hostRemoval,
      ),
    );
    await _flushUntil(
      () => _harness.hookReceiver.clearedSessionIds.contains('second-session'),
    );

    expect(_controller.state.tabsFor(workspace.id), contains(second));
    expect(_harness.terminalRuntime.releasedTabIds, isEmpty);
  });

  test('a terminal that quits beside a running one still closes', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final second = await _openSecondTerminal(workspace, terminal);
    _handleFor(workspace, second);
    await _handleFor(workspace, terminal).ensureStarted();

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: second.id,
        exitCode: 0,
      ),
    );
    await _flushUntil(
      () => !_controller.state
          .tabsFor(workspace.id)
          .any((tab) => tab.id == second.id),
    );
  });

  test('a sleep removal keeps its tab after another client woke it', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _handleFor(workspace, terminal).terminalSessionId = 'slept-session';
    // The phone already woke the workspace, so the host lists nothing slept.
    _harness.workbenchRepository.sleptTabs = const <String, List<String>>{};

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: -1,
        cause: const .workspaceSleep(),
      ),
    );
    await _flushUntil(
      () => _harness.hookReceiver.clearedSessionIds.contains('slept-session'),
    );

    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
    expect(_harness.terminalRuntime.releasedTabIds, <String>[terminal.id]);
    expect(_harness.terminalRuntime.closedTabIds, isNot(contains(terminal.id)));
  });

  test('a named sleep settles while its siblings are still stopping', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final second = await _openSecondTerminal(workspace, terminal);
    _handleFor(workspace, second);
    // The host has not removed the first terminal yet.
    await _handleFor(workspace, terminal).ensureStarted();

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: second.id,
        exitCode: -1,
        cause: const .workspaceSleep(),
      ),
    );
    await _flushUntil(() => _controller.state.activeWorkspace == null);

    expect(_controller.state.tabsFor(workspace.id), contains(second));
    expect(_harness.terminalRuntime.releasedTabIds, <String>[second.id]);
  });

  test('an evicted handle still gets its slept session cleaned up', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _handleFor(workspace, terminal).terminalSessionId = 'evicted-session';
    final gate = Completer<void>();
    _harness.workbenchRepository
      ..sleptTabs = <String, List<String>>{
        workspace.id: <String>[terminal.id],
      }
      ..sleptTabsGate = gate;

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: -1,
      ),
    );
    await _flush();
    // The buffer budget drops the handle while the older host answers.
    _harness.terminalRuntime.releaseTab(terminal.id);
    gate.complete();
    await _flushUntil(
      () => _harness.hookReceiver.clearedSessionIds.contains('evicted-session'),
    );

    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
  });

  test('a queued exit is dropped once its terminal runs again', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final handle = _handleFor(workspace, terminal);
    final gate = Completer<void>();
    _harness.workbenchRepository.sleptTabsGate = gate;

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: -1,
      ),
    );
    await _flush();
    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: 0,
      ),
    );
    await _flush();
    // The tab starts again, with a new agent, before the first exit finishes.
    await handle.ensureStarted();
    final now = DateTime.now().toUtc();
    final agentStatus = _harness.container.read(
      agentStatusControllerProvider.notifier,
    );
    agentStatus.replaceRuntimeSnapshot(<AgentStatusEntry>[
      AgentStatusEntry(
        terminalSessionId: 'new-session',
        workspaceId: workspace.id,
        tabId: terminal.id,
        agentType: AgentType.codex,
        state: AgentStatusState.working,
        prompt: '',
        updatedAt: now,
        stateStartedAt: now,
      ),
    ]);
    _harness.workbenchRepository.sleptTabsGate = null;
    gate.complete();
    await _flush();
    await _flush();

    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
    expect(_harness.terminalRuntime.peekSession(terminal.id), same(handle));
    expect(
      _harness.container
          .read(agentStatusControllerProvider)['new-session']
          ?.state,
      AgentStatusState.working,
    );
  });

  test('a reopen between removals of one sleep stays open', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final second = await _openSecondTerminal(workspace, terminal);
    _handleFor(workspace, terminal);
    _handleFor(workspace, second);
    TerminalRuntimeExitEvent removal(String tabId) => TerminalRuntimeExitEvent(
      workspaceId: workspace.id,
      tabId: tabId,
      exitCode: -1,
      cause: const .workspaceSleep(),
    );

    _harness.terminalRuntime.emitExit(removal(terminal.id));
    await _flushUntil(() => _controller.state.activeWorkspace == null);
    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    _harness.terminalRuntime.emitExit(removal(second.id));
    await _flushUntil(
      () =>
          _controller.state.sleptTabIdsByWorkspaceId[workspace.id]?.contains(
            second.id,
          ) ??
          false,
    );

    expect(_controller.state.activeWorkspace?.id, workspace.id);
    // The reopened workspace keeps the exited handle its surface shows.
    expect(_harness.terminalRuntime.releasedTabIds, <String>[terminal.id]);
  });

  test('a second sleep closes the workspace again', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    TerminalRuntimeExitEvent removal(String sleepId) =>
        TerminalRuntimeExitEvent(
          workspaceId: workspace.id,
          tabId: terminal.id,
          exitCode: -1,
          cause: .workspaceSleep(sleepId),
        );

    _handleFor(workspace, terminal);
    _harness.terminalRuntime.emitExit(removal('sleep-1'));
    await _flushUntil(() => _controller.state.activeWorkspace == null);
    // Woken and slept again before any snapshot showed it awake.
    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    _handleFor(workspace, terminal);
    _harness.terminalRuntime.emitExit(removal('sleep-2'));
    await _flushUntil(() => _controller.state.activeWorkspace == null);
  });

  test('a local sleep does not close a workspace reopened meanwhile', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _handleFor(workspace, terminal);
    _harness.workbenchRepository.onSleep = () async {
      // The host's removal arrives before its answer, and the user reopens.
      _harness.terminalRuntime.emitExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspace.id,
          tabId: terminal.id,
          exitCode: -1,
          cause: const .workspaceSleep('local-sleep'),
        ),
      );
      await _flushUntil(() => _controller.state.activeWorkspace == null);
      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: workspace,
      );
    };

    await _controller.sleepWorkspace(workspace);

    expect(_controller.state.activeWorkspace?.id, workspace.id);
    expect(_harness.terminalRuntime.closedWorkspaceIds, isEmpty);
  });

  test('kept exited handles are freed once their workspace is left', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _harness.container.read(terminalRuntimeActiveWorkspaceCoordinatorProvider);
    final second = await _openSecondTerminal(workspace, terminal);
    _handleFor(workspace, terminal);
    _handleFor(workspace, second);
    TerminalRuntimeExitEvent removal(String tabId) => TerminalRuntimeExitEvent(
      workspaceId: workspace.id,
      tabId: tabId,
      exitCode: -1,
      cause: const .workspaceSleep('sleep-1'),
    );
    _harness.terminalRuntime.emitExit(removal(terminal.id));
    await _flushUntil(() => _controller.state.activeWorkspace == null);
    await _controller.selectWorkspace(
      project: _harness.project,
      workspace: workspace,
    );
    _harness.terminalRuntime.emitExit(removal(second.id));
    await _flushUntil(
      () =>
          _controller.state.sleptTabIdsByWorkspaceId[workspace.id]?.contains(
            second.id,
          ) ??
          false,
    );
    expect(_harness.terminalRuntime.releasedTabIds, isNot(contains(second.id)));

    final other = await _harness.addProject('other', 'Other');
    await _flushUntil(
      () => _controller.state.workspacesFor(other.id).isNotEmpty,
    );
    await _controller.selectWorkspace(
      project: other,
      workspace: _controller.state.workspacesFor(other.id).single,
    );
    await _flushUntil(
      () => _harness.terminalRuntime.releasedTabIds.contains(second.id),
    );
  });
}
