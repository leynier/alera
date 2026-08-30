part of 'alera_shell_page_test.dart';

const Key _statusGlyphKey = ValueKey<String>('workspace-status-glyph');

void _registerAleraShellSidebarIdentityTests() {
  testWidgets('a workspace row keeps its element when rows reorder', (
    tester,
  ) async {
    // Rows sort by live agent activity, so without stable keys the list
    // re-matches elements by index and row content slides between them.
    final state = _stackedWorkbenchState();
    final harness = await _pumpShell(tester, state: state);
    final rowKey = ValueKey<String>(
      'workspace:all:${_firstWorkspaceId(state)}',
    );
    final before = tester.element(find.byKey(rowKey));

    harness.agentStatus.setEntries(<String, AgentStatusEntry>{
      'tab-2': _agentStatusEntry(
        terminalSessionId: 'tab-2',
        workspaceId: 'workspace-2',
        tabId: 'tab-2',
        state: .waiting,
      ),
    });
    await tester.pump();

    expect(identical(tester.element(find.byKey(rowKey)), before), isTrue);
  });

  testWidgets('the status slot keeps its element when an agent starts', (
    tester,
  ) async {
    // Swapping widget types in this slot destroyed the element and restarted
    // the spinner from zero, which is the stutter under orchestration load.
    final state = _stackedWorkbenchState();
    final harness = await _pumpShell(tester, state: state);
    final before = tester.element(find.byKey(_statusGlyphKey).first);

    harness.agentStatus.setEntries(<String, AgentStatusEntry>{
      'tab-1': _agentStatusEntry(
        terminalSessionId: 'tab-1',
        workspaceId: 'workspace-1',
        tabId: 'tab-1',
        state: .working,
      ),
    });
    await tester.pump();

    expect(
      identical(tester.element(find.byKey(_statusGlyphKey).first), before),
      isTrue,
    );
  });

  testWidgets('working agents share a single spinner ticker', (tester) async {
    final state = _stackedWorkbenchState();
    await _pumpShell(
      tester,
      state: state,
      agentStatuses: <String, AgentStatusEntry>{
        'tab-1': _agentStatusEntry(
          terminalSessionId: 'tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          state: .working,
        ),
        'tab-2': _agentStatusEntry(
          terminalSessionId: 'tab-2',
          workspaceId: 'workspace-2',
          tabId: 'tab-2',
          state: .working,
        ),
      },
    );

    expect(find.byType(AgentRunSharedSpinner), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

String _firstWorkspaceId(WorkbenchState state) {
  return state.workspacesByProject.values.first.first.id;
}
