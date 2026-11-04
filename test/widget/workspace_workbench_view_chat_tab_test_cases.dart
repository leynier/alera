part of 'workspace_workbench_view_test.dart';

final class _TitleLifecycle extends AgentChatLifecycleRepository {
  final List<(String, bool)> regenerated = <(String, bool)>[];

  @override
  Future<void> regenerateTitle(
    AgentChatRef chat, {
    required String requestId,
    bool replaceUserTitle = false,
  }) async => regenerated.add((chat.chatId, replaceUserTitle));
}

void _registerWorkspaceWorkbenchViewChatTabTests() {
  testWidgets('a chat tab renames and regenerates the chat, not the tab', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository();
    final lifecycle = _TitleLifecycle();
    final tabs = <WorkspaceTabRecord>[
      _tab('tab-1', title: 'Terminal 1'),
      _tab(
        'tab-2',
        title: 'Fix the login crash',
        kind: WorkspaceTabKind.agentChat,
        chatId: 'chat-1',
      ),
    ];
    await _pumpWorkbenchView(
      tester,
      tabs: tabs,
      terminalRuntime: terminalRuntime,
      layout: .single(
        workspaceId: _workspaceId,
        groupId: 'group-a',
        tabIds: tabs.map((tab) => tab.id).toList(),
      ),
      createdTabs: createdTabs,
      selectedTabs: selectedTabs,
      closedTabs: closedTabs,
      closedTabGroups: closedTabGroups,
      renamedTabs: renamedTabs,
      movedTabs: movedTabs,
      splitGroups: splitGroups,
      mergedGroups: mergedGroups,
      updatedRatios: updatedRatios,
      overrides: [
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatCapabilityProvider(AgentChatWire.titleGenerationCapability)
            .overrideWith((ref) async => true),
      ],
    );

    await _openTabContextMenu(tester, 'Fix the login crash');
    await tester.tap(find.text('Change Title'));
    await tester.pumpAndSettle();
    expect(find.text('Change Chat Title'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Login Crash');
    await tester.tap(find.text('Change Title').last);
    await tester.pumpAndSettle();
    expect(repository.calls, contains(('rename', 'Login Crash')));
    expect(renamedTabs, isEmpty);

    await _openTabContextMenu(tester, 'Fix the login crash');
    await tester.tap(find.text('Regenerate Title'));
    await tester.pumpAndSettle();
    expect(lifecycle.regenerated, <(String, bool)>[('chat-1', true)]);

    // A terminal tab keeps its own rename and offers no chat title action.
    await _openTabContextMenu(tester, 'Terminal 1');
    expect(find.text('Regenerate Title'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });
}
