part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerSleepExitTests() {
  test('an exit caused by a sleep from another client keeps the tab', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final tabCount = _controller.state.tabsFor(workspace.id).length;
    (_harness.terminalRuntime.sessionFor(
      workspace: workspace,
      tab: terminal,
    ) as _FakeTerminalSessionHandle).terminalSessionId = 'slept-session';
    // The host records the slept tabs before it ends their sessions.
    _harness.workbenchRepository.sleptTabs = <String, List<String>>{
      workspace.id: <String>[terminal.id],
    };

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: -1,
      ),
    );
    await _flushUntil(() => _controller.state.activeWorkspace == null);

    expect(_controller.state.tabsFor(workspace.id), hasLength(tabCount));
    expect(
      await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      contains(predicate<WorkspaceTabRecord>((tab) => tab.id == terminal.id)),
    );
    expect(_controller.state.sleptTabIdsByWorkspaceId[workspace.id], <String>[
      terminal.id,
    ]);
    // The session is already gone on the host, so the handle is released
    // for the wake instead of being terminated.
    expect(_harness.terminalRuntime.releasedTabIds, <String>[terminal.id]);
    expect(_harness.terminalRuntime.closedTabIds, isNot(contains(terminal.id)));
    // A close would have dropped the Codex transcript watch; a release has
    // to do it explicitly.
    await _flushUntil(
      () => _harness.hookReceiver.clearedSessionIds.contains('slept-session'),
    );
  });

  test('a terminal that exits on its own still closes its tab', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _harness.workbenchRepository.sleptTabs = <String, List<String>>{
      'another-workspace': <String>[terminal.id],
    };

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: 0,
      ),
    );
    await _flushUntil(
      () => !_controller.state
          .tabsFor(workspace.id)
          .any((tab) => tab.id == terminal.id),
    );

    expect(
      await _harness.workbenchRepository.listWorkspaceTabs(workspace.id),
      isNot(
        contains(predicate<WorkspaceTabRecord>((tab) => tab.id == terminal.id)),
      ),
    );
    expect(_harness.terminalRuntime.releasedTabIds, isEmpty);
  });

  test('settling a sleep elsewhere keeps the active workspace', () async {
    final (workspace, _) = await _selectWithTerminal();

    _controller.settleSleptTerminal('another-workspace', 't-1', <String>[
      't-1',
    ]);

    expect(_controller.state.activeWorkspace?.id, workspace.id);
    expect(_harness.terminalRuntime.releasedTabIds, <String>['t-1']);
  });

  test('a terminal opened after the sleep stays awake', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final newer = await _openSecondTerminal(workspace, terminal);
    _handleFor(workspace, newer);

    _controller.settleSleptTerminal(workspace.id, terminal.id, <String>[
      terminal.id,
    ]);

    expect(_controller.state.sleptTabIdsByWorkspaceId[workspace.id], <String>[
      terminal.id,
    ]);
    expect(_harness.terminalRuntime.peekSession(newer.id), isNotNull);
    expect(_harness.terminalRuntime.releasedTabIds, <String>[terminal.id]);
  });

  test('every slept session is cleaned up, not only the first', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final second = await _openSecondTerminal(workspace, terminal);
    _handleFor(workspace, terminal).terminalSessionId = 'session-1';
    _handleFor(workspace, second).terminalSessionId = 'session-2';
    _harness.workbenchRepository.sleptTabs = <String, List<String>>{
      workspace.id: <String>[terminal.id, second.id],
    };

    for (final tab in <WorkspaceTabRecord>[terminal, second]) {
      _harness.terminalRuntime.emitExit(
        TerminalRuntimeExitEvent(
          workspaceId: workspace.id,
          tabId: tab.id,
          exitCode: -1,
        ),
      );
    }
    await _flushUntil(
      () => _harness.hookReceiver.clearedSessionIds.length == 2,
    );

    expect(
      _harness.hookReceiver.clearedSessionIds,
      unorderedEquals(<String>['session-1', 'session-2']),
    );
    expect(
      _harness.terminalRuntime.releasedTabIds,
      unorderedEquals(<String>[terminal.id, second.id]),
    );
    expect(_controller.state.tabsFor(workspace.id), hasLength(2));
  });

  test('a wake during the host lookup discards the stale settlement', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _handleFor(workspace, terminal).terminalSessionId = 'old-session';
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
    // Reopening the workspace starts a new session for the same tab id.
    _harness.terminalRuntime.releaseTab(terminal.id);
    final woken = _handleFor(workspace, terminal);
    _harness.terminalRuntime.releasedTabIds.clear();
    gate.complete();
    await _flush();
    await _flush();

    expect(_harness.terminalRuntime.peekSession(terminal.id), same(woken));
    expect(_harness.terminalRuntime.releasedTabIds, isEmpty);
    expect(_controller.state.activeWorkspace?.id, workspace.id);
    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
    expect(_harness.hookReceiver.clearedSessionIds, isEmpty);
  });

  test('a restart in progress keeps the tab of the stale exit', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    final handle = _handleFor(workspace, terminal);
    final gate = Completer<void>();
    _harness.workbenchRepository.sleptTabsGate = gate;

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: 0,
      ),
    );
    await _flush();
    handle.starting = true;
    gate.complete();
    await _flush();
    await _flush();

    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
    expect(_harness.terminalRuntime.peekSession(terminal.id), same(handle));
  });

  test('a slept auto-close terminal is settled, not kept as failed', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _handleFor(workspace, terminal).terminalSessionId = 'setup-session';
    _harness.workbenchRepository.sleptTabs = <String, List<String>>{
      workspace.id: <String>[terminal.id],
    };

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: -1,
        autoCloseOnSuccess: true,
      ),
    );
    await _flushUntil(
      () => _harness.hookReceiver.clearedSessionIds.contains('setup-session'),
    );

    expect(_harness.terminalRuntime.releasedTabIds, <String>[terminal.id]);
    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
  });

  test('an exit during the first start still closes its tab', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _handleFor(workspace, terminal).starting = true;

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: 0,
      ),
    );
    await _flushUntil(
      () => !_controller.state
          .tabsFor(workspace.id)
          .any((tab) => tab.id == terminal.id),
    );
  });

  test('a failed sleep lookup keeps the tab but clears the session', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    _handleFor(workspace, terminal).terminalSessionId = 'lost-session';
    _harness.workbenchRepository.sleptTabsError = StateError('host lost');

    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: -1,
      ),
    );
    await _flushUntil(
      () => _harness.hookReceiver.clearedSessionIds.contains('lost-session'),
    );

    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
  });

  test('a handle opened during the lookup keeps the tab', () async {
    final (workspace, terminal) = await _selectWithTerminal();
    // A local sleep already dropped the handle when the exit is handled.
    expect(_harness.terminalRuntime.peekSession(terminal.id), isNull);
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
    // Reopening wakes the workspace, so the host no longer lists the tab.
    final woken = _handleFor(workspace, terminal);
    gate.complete();
    await _flush();
    await _flush();

    expect(_controller.state.tabsFor(workspace.id), contains(terminal));
    expect(_harness.terminalRuntime.peekSession(terminal.id), same(woken));
  });

  test('a reopened terminal that quits during the lookup is closed', () async {
    final (workspace, terminal) = await _selectWithTerminal();
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
    // The reopened terminal starts and quits before the lookup answers.
    _handleFor(workspace, terminal);
    _harness.terminalRuntime.emitExit(
      TerminalRuntimeExitEvent(
        workspaceId: workspace.id,
        tabId: terminal.id,
        exitCode: 0,
      ),
    );
    await _flush();
    _harness.workbenchRepository.sleptTabsGate = null;
    gate.complete();
    await _flushUntil(
      () => !_controller.state
          .tabsFor(workspace.id)
          .any((tab) => tab.id == terminal.id),
    );
  });
}

Future<(Workspace, WorkspaceTabRecord)> _selectWithTerminal() async {
  await _controller.bootstrap();
  final workspace = await _selectMainWorkspace(_controller, _harness);
  await _flushUntil(
    () => _controller.state
        .tabsFor(workspace.id)
        .any((tab) => tab.kind == WorkspaceTabKind.terminal),
  );
  final terminal = _controller.state
      .tabsFor(workspace.id)
      .firstWhere((tab) => tab.kind == WorkspaceTabKind.terminal);
  _harness.container.read(terminalRuntimeExitCoordinatorProvider);
  return (workspace, terminal);
}

Future<WorkspaceTabRecord> _openSecondTerminal(
  Workspace workspace,
  WorkspaceTabRecord terminal,
) async {
  final second = WorkspaceTabRecord(
    id: 'second-terminal',
    workspaceId: workspace.id,
    title: 'Terminal 2',
    createdAt: terminal.createdAt,
    updatedAt: terminal.updatedAt,
  );
  await _harness.workbenchRepository.upsertWorkspaceTab(second);
  _harness.workbenchRepository.emitTabs(workspace.id);
  await _flushUntil(
    () => _controller.state
        .tabsFor(workspace.id)
        .any((tab) => tab.id == second.id),
  );
  return second;
}

_FakeTerminalSessionHandle _handleFor(
  Workspace workspace,
  WorkspaceTabRecord tab,
) =>
    _harness.terminalRuntime.sessionFor(workspace: workspace, tab: tab)
        as _FakeTerminalSessionHandle;
