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

  testWidgets('Ask Agent opens the inbox composer for that terminal', (
    tester,
  ) async {
    final inbox = InboxTestClient()
      ..respond('inbox.summary', const <String, Object?>{'items': <Object?>[]})
      ..respond('inbox.threads', const <String, Object?>{'items': <Object?>[]})
      ..respond('inbox.targets', <String, Object?>{
        'items': [
          {
            'handle': 'session-7',
            'sessionLive': true,
            'workspaceId': 'workspace-1',
            'agent': 'codex',
            'deliveryMode': 'paste',
            'tabTitle': 'Terminal 2',
          },
        ],
      });
    await _pumpShell(
      tester,
      state: _stackedWorkbenchState().copyWith(
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          'workspace-1': <WorkspaceTabRecord>[
            WorkspaceTabRecord(
              id: 'tab-1',
              workspaceId: 'workspace-1',
              title: 'Terminal 1',
              createdAt: DateTime.utc(2026, 5, 22),
              updatedAt: DateTime.utc(2026, 5, 22),
            ),
            WorkspaceTabRecord(
              id: 'tab-2',
              workspaceId: 'workspace-1',
              title: 'Terminal 2',
              createdAt: DateTime.utc(2026, 5, 22),
              updatedAt: DateTime.utc(2026, 5, 22),
              payload: const <String, Object?>{
                'terminalSessionId': 'session-7',
              },
            ),
          ],
        },
      ),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-1': _agentStatusEntry(
          terminalSessionId: 'tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          state: .waiting,
          lastAssistantMessage: 'Other agent',
        ),
        'session-7': _agentStatusEntry(
          terminalSessionId: 'session-7',
          workspaceId: 'workspace-1',
          tabId: 'tab-2',
          state: .waiting,
          lastAssistantMessage: 'Ready to continue',
        ),
      },
      inboxClient: inbox,
    );
    await tester.tap(find.byTooltip('Show Agent Runs'));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(ProjectWorkbenchSidebar),
          matching: find.text('Ready to continue'),
        ),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Regenerate Title'), findsNothing);
    await tester.tap(find.text('Ask Agent'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxComposerDialog), findsOneWidget);
    expect(
      tester
          .widget<InboxComposerDialog>(find.byType(InboxComposerDialog))
          .initialTarget,
      'session-7',
    );
    expect(find.textContaining('Terminal 2'), findsWidgets);
  });
}
