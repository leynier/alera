part of 'alera_shell_page_test.dart';

void _registerAleraShellQueueCloseTests() {
  for (final unbound in [false, true]) {
    for (final outcome in ['queue-cancel', 'editor-cancel', 'close']) {
      testWidgets(
        'bulk close defers queue cancellation until $outcome (unbound: $unbound)',
        (tester) async {
          final client = _ShellCodexClient(
            sharedQueues: true,
            unboundQueue: unbound,
          );
          final initial = _stackedWorkbenchState();
          final first = initial.tabsFor('workspace-1').first;
          final tabs = [
            first,
            for (var i = 1; i <= 2; i++)
              first.copyWith(
                id: 'chat-$i',
                title: 'Chat $i',
                kind: WorkspaceTabKind.codex,
              ),
            first.copyWith(
              id: 'editor',
              title: 'Notes',
              kind: WorkspaceTabKind.editor,
            ),
          ];
          final registry = EditorSessionRegistry();
          addTearDown(registry.dispose);
          registry.register(
            'editor',
            EditorSessionHandle(
              isDirty: () => true,
              save: () async {},
              discard: () async {},
            ),
          );
          final harness = await _pumpShell(
            tester,
            codexClient: client,
            editorSessionRegistry: registry,
            state: initial.copyWith(
              tabsByWorkspace: {'workspace-1': tabs},
              activeTabIdByWorkspace: {'workspace-1': first.id},
              layoutByWorkspace: {
                'workspace-1':
                    WorkbenchLayout.single(
                      workspaceId: 'workspace-1',
                      tabIds: tabs.map((tab) => tab.id).toList(),
                    ).setActiveTab(
                      groupId: WorkbenchLayout.defaultGroupId('workspace-1'),
                      tabId: first.id,
                    ),
              },
            ),
          );
          final tabHandles = find.byWidgetPredicate(
            (widget) => widget is Draggable,
          );
          await tester.tapAt(
            tester.getCenter(tabHandles.first),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Close Others'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, 'Cancel Messages And Close'),
          );
          await tester.pumpAndSettle();
          expect(client.cancelledTabs, isEmpty);
          await tester.tap(
            find
                .text(
                  outcome == 'queue-cancel'
                      ? 'Cancel'
                      : 'Cancel Messages And Close',
                )
                .last,
          );
          await tester.pumpAndSettle();
          expect(client.cancelledTabs, isEmpty);
          if (outcome != 'queue-cancel') {
            expect(find.text('Close Unsaved Editor?'), findsOneWidget);
            await tester.tap(
              find.text(outcome == 'editor-cancel' ? 'Cancel' : 'Close').last,
            );
            await tester.pumpAndSettle();
          }
          expect(
            client.cancelledTabs,
            outcome == 'close' ? ['chat-1', 'chat-2'] : isEmpty,
          );
          expect(
            harness.controller.state.tabsFor('workspace-1'),
            hasLength(outcome == 'close' ? 1 : 4),
          );
        },
      );
    }
  }
}
