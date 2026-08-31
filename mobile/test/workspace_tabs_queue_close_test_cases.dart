part of 'workspace_tabs_screen_test.dart';

void _registerQueueCloseRecoveryTests() {
  for (final unbound in [false, true]) {
    testWidgets('closes a shared queue after recovery (unbound: $unbound)', (
      tester,
    ) async {
      final terminal = _QueueCloseTerminalClient(unbound: unbound)
        ..tabs = [fakeTab(id: 'codex-1', title: 'Chat', kind: 'codex')];
      final codex = FakeMobileCodexClient();
      addTearDown(terminal.dispose);
      addTearDown(codex.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            terminalClientProvider(
              'host-1',
            ).overrideWith((ref) async => terminal),
            workspaceClientProvider(
              'host-1',
            ).overrideWith((ref) async => terminal),
            mobileCodexClientProvider(
              'host-1',
            ).overrideWith((ref) async => codex),
          ],
          child: const MaterialApp(
            home: WorkspaceTabsScreen(
              hostId: 'host-1',
              workspace: WorkspaceSummary(
                id: 'workspace-1',
                projectId: 'project-1',
                name: 'Workspace',
                path: '/repo',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close Tab'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Closing this tab cancels its queued messages for every connected client.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(terminal.cancelled, isTrue);
      expect(terminal.calls, contains('removeTab codex-1'));
      expect(tester.takeException(), isNull);
    });
  }
}

class _QueueCloseTerminalClient extends FakeTerminalClient
    implements MobileCodexClient {
  _QueueCloseTerminalClient({required this.unbound});
  final bool unbound;
  bool cancelled = false;
  @override
  bool get supportsCodexChat => true;
  @override
  bool get supportsCodexGoals => false;
  @override
  bool get supportsCodexSessions => true;
  @override
  bool get supportsCodexTurnPolicy => true;
  @override
  Future<WorkspaceTabSummary> createCodexTab(String workspaceId) async =>
      throw UnimplementedError();
  @override
  Future<Map<String, Object?>> codexRequest(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async {
    final queue = <String, Object?>{
      'threadId': unbound ? '' : 'thread',
      'revision': 0,
      'messages': [],
      'otherQueues': [
        {'threadId': 'previous', 'revision': 4},
      ],
    };
    if (type == 'codex.thread.snapshot') return {'queue': queue};
    if (type == 'codex.queue.get') return queue;
    if (type == 'codex.queue.cancel') {
      expect(payload['expectedThreadId'], unbound ? isNull : 'thread');
      expect(payload['otherQueues'], [
        {'threadId': 'previous', 'revision': 4},
      ]);
      cancelled = true;
      return queue;
    }
    throw StateError('Unexpected request: $type');
  }
}
