part of 'alera_shell_page_test.dart';

void _registerAleraShellCodexSidebarTests() {
  testWidgets('Codex chat runs select and close their native tab', (
    tester,
  ) async {
    final base = _linkedWorkbenchState(linkedExpanded: true);
    final terminal = base.tabsFor('workspace-2').single;
    final codexTab = WorkspaceTabRecord(
      id: terminal.id,
      workspaceId: terminal.workspaceId,
      kind: WorkspaceTabKind.codex,
      title: 'Codex',
      createdAt: terminal.createdAt,
      updatedAt: terminal.updatedAt,
    );
    final state = base.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ...base.tabsByWorkspace,
        'workspace-2': <WorkspaceTabRecord>[codexTab],
      },
    );
    final handle = 'codex:${codexTab.id}';
    final harness = await _pumpShell(
      tester,
      state: state,
      agentStatuses: <String, AgentStatusEntry>{
        handle: _agentStatusEntry(
          terminalSessionId: handle,
          workspaceId: codexTab.workspaceId,
          tabId: codexTab.id,
          state: AgentStatusState.waiting,
          prompt: 'Review the workspace',
        ),
      },
    );

    const description = 'Codex · Waiting for input';
    await tester.tap(find.text(description));
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.controller.state.activeWorkspaceId, 'workspace-2');
    expect(
      harness.controller.state.activeTabIdByWorkspace['workspace-2'],
      codexTab.id,
    );
    expect(harness.runtime.focusedTabIds, isNot(contains(codexTab.id)));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text(description)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Close Codex'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.runtime.closedTabIds, isEmpty);
    expect(harness.controller.state.tabsFor('workspace-2'), isEmpty);
    expect(find.text(description), findsNothing);
  });
}
