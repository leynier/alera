part of 'alera_shell_page_test.dart';

void _registerAleraShellSidebarTitleTests() {
  testWidgets('sidebar agent rows can show tab titles and regenerate them', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      state: _stackedWorkbenchState().copyWith(
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          'workspace-1': <WorkspaceTabRecord>[
            WorkspaceTabRecord(
              id: 'tab-1',
              workspaceId: 'workspace-1',
              title: 'Map Monetization',
              createdAt: DateTime.utc(2026, 5, 22),
              updatedAt: DateTime.utc(2026, 5, 22),
              payload: const <String, Object?>{
                'agentTitleSource': 'generated',
                'manualTitle': true,
              },
            ),
            WorkspaceTabRecord(
              id: 'tab-2',
              workspaceId: 'workspace-1',
              title: 'Terminal 2',
              createdAt: DateTime.utc(2026, 5, 22),
              updatedAt: DateTime.utc(2026, 5, 22),
            ),
          ],
        },
      ),
      settings: AleraSettings.defaults.copyWith(
        agents: const AgentSettings(showTabTitlesInSidebar: true),
      ),
      agentTitlesAvailable: true,
      agentStatuses: <String, AgentStatusEntry>{
        'tab-1': _agentStatusEntry(
          terminalSessionId: 'tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          state: .waiting,
          lastAssistantMessage: '**paymentBroker**',
        ),
        'tab-2': _agentStatusEntry(
          terminalSessionId: 'tab-2',
          workspaceId: 'workspace-1',
          tabId: 'tab-2',
          state: .waiting,
          lastAssistantMessage: 'Ready to continue',
        ),
      },
    );

    await tester.tap(find.byTooltip('Show Agent Runs'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ProjectWorkbenchSidebar),
        matching: find.text('Map Monetization'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ProjectWorkbenchSidebar),
        matching: find.text('**paymentBroker**'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ProjectWorkbenchSidebar),
        matching: find.text('Ready to continue'),
      ),
      findsNothing,
    );

    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(ProjectWorkbenchSidebar),
          matching: find.text('Map Monetization'),
        ),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Regenerate Title'), findsOneWidget);
    final entry = tester.widget<AleraDropdownEntry<Object?>>(
      find.ancestor(
        of: find.text('Regenerate Title'),
        matching: find.byWidgetPredicate(
          (widget) => widget is AleraDropdownEntry,
        ),
      ),
    );
    expect((entry.leading! as Icon).size, 16);
  });
}
