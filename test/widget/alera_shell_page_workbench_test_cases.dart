part of 'alera_shell_page_test.dart';

void _registerAleraShellWorkbenchTests() {
  testWidgets('shell renders the terminal workbench for the active workspace', (
    tester,
  ) async {
    await _pumpShell(tester, state: _populatedWorkbenchState());

    expect(find.byTooltip('New Tab'), findsOneWidget);
    expect(find.text('New Terminal'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(find.text('No workspace selected'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'WorkbenchStatusBar',
      ),
      findsNothing,
    );
    expect(find.text('/repo/alera'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Add Project'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('workspace and tab surfaces show agent status indicators', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-1': _agentStatusEntry(
          terminalSessionId: 'tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          state: .waiting,
        ),
      },
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'Codex waiting',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'Waiting for input',
      ),
      findsWidgets,
    );
  });

  testWidgets('shell renders split terminal panes for one workspace', (
    tester,
  ) async {
    await _pumpShell(tester, state: _splitWorkbenchState());

    expect(find.byTooltip('New Tab'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsOneWidget,
    );
  });

  testWidgets('focused split panes promote their workbench group', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _splitWorkbenchState());
    final before = harness.controller.state.layoutFor('workspace-1')!;
    final paneFocus = tester.widget<Focus>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Focus &&
                widget.onFocusChange != null &&
                widget.canRequestFocus == false &&
                widget.skipTraversal == true,
          )
          .first,
    );

    paneFocus.onFocusChange!(true);
    await tester.pump();

    expect(
      harness.controller.state.layoutFor('workspace-1')!.activeGroupId,
      isNot(before.activeGroupId),
    );
  });

  testWidgets('dragging a tab to a pane edge creates a directional split', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpShell(tester, state: _stackedWorkbenchState());

    final tabs = find.byWidgetPredicate((widget) => widget is Draggable);
    expect(tabs, findsNWidgets(2));
    expect(find.byTooltip('New Tab'), findsOneWidget);

    final secondTabStart = tester.getTopLeft(tabs.at(1)) + const Offset(24, 20);
    final terminalRect = tester.getRect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
    );
    final target = Offset(terminalRect.right - 48, terminalRect.center.dy);
    final gesture = await tester.startGesture(secondTabStart);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 96));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byTooltip('New Tab'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsOneWidget,
    );
  });

  testWidgets('tab context menu exposes split, close, and title actions', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _stackedWorkbenchState());

    final tabs = find.byWidgetPredicate((widget) => widget is Draggable);
    await tester.tapAt(
      tester.getCenter(tabs.first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Split Up'), findsOneWidget);
    expect(find.text('Split Down'), findsOneWidget);
    expect(find.text('Split Left'), findsOneWidget);
    expect(find.text('Split Right'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Close Others'), findsOneWidget);
    expect(find.text('Close Tabs to the Right'), findsOneWidget);
    expect(find.text('Change Title'), findsOneWidget);

    await tester.tap(find.text('Close Tabs to the Right'));
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(
      harness.controller.state.tabsFor('workspace-1').map((tab) => tab.id),
      <String>['tab-1'],
    );
  });

  testWidgets('shell shows the empty state when there are no projects', (
    tester,
  ) async {
    await _pumpShell(tester, state: const WorkbenchState(bootstrapped: true));

    expect(find.text('No projects yet'), findsAtLeastNWidgets(1));
    expect(
      find.widgetWithText(FilledButton, 'Add Your First Project'),
      findsOneWidget,
    );
  });

  testWidgets('shell shows the empty state when no workspace is selected', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      state: _populatedWorkbenchState().copyWith(activeWorkspaceId: null),
    );

    expect(find.text('Welcome to Alera'), findsOneWidget);
    expect(find.text('Quick Start'), findsOneWidget);
    expect(find.text('Keyboard Shortcuts'), findsOneWidget);
    expect(find.text('Projects & Workspaces'), findsNothing);
    expect(find.byTooltip('New Tab'), findsNothing);
  });

  testWidgets('terminal exit closes its tab and activates the remaining tab', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _stackedWorkbenchState());

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-2');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(
      harness.controller.state.tabsFor('workspace-1').map((tab) => tab.id),
      <String>['tab-1'],
    );
    expect(harness.controller.state.activeWorkspaceId, 'workspace-1');
    expect(harness.controller.state.activeWorkspaceTab?.id, 'tab-1');
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-2')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsOneWidget,
    );
  });

  testWidgets('terminal exit closes the last tab and deselects the workspace', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-1');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-1']);
    expect(harness.controller.state.tabsFor('workspace-1'), isEmpty);
    expect(harness.controller.state.activeWorkspace, isNull);
    expect(find.text('Welcome to Alera'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fake-terminal-tab-1')),
      findsNothing,
    );
  });

  testWidgets('terminal exit closes tabs even when no workspace is selected', (
    tester,
  ) async {
    final harness = await _pumpShell(
      tester,
      state: _populatedWorkbenchState().copyWith(activeWorkspaceId: null),
    );

    harness.runtime.emitExit(workspaceId: 'workspace-1', tabId: 'tab-1');
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-1']);
    expect(harness.controller.state.tabsFor('workspace-1'), isEmpty);
    expect(harness.controller.state.activeWorkspace, isNull);
    expect(find.text('Welcome to Alera'), findsOneWidget);
  });

  testWidgets('clicking new-terminal button focuses the new session', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Terminal'));
    // First pump runs the await chain; the second pump runs the
    // post-frame callback that requestFocus() defers to.
    await tester.pump();
    await tester.pump();

    expect(harness.runtime.totalFocusRequests, 1);
  });

  testWidgets('new-terminal shortcut focuses the new session', (tester) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    // Focus a descendant so key events bubble up to the global scope.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.keyT);
    await tester.sendKeyUpEvent(.keyT);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, 1);
  });

  testWidgets('split shortcut focuses the new pane terminal', (tester) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();

    // Ctrl+Shift+D is the split-right default off macOS.
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyDownEvent(.shiftLeft);
    await tester.sendKeyDownEvent(.keyD);
    await tester.sendKeyUpEvent(.keyD);
    await tester.sendKeyUpEvent(.shiftLeft);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, 1);
  });

  testWidgets('workspace context menu shows supported workspace actions', (
    tester,
  ) async {
    final opener = WorkspaceFolderOpener(
      processRunner: _NoopProcessRunner(),
      platform: .macos,
      directoryExists: (_) async => true,
    );
    await _pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      workspaceFolderOpener: opener,
    );

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Manage Tags'), findsOneWidget);
    expect(find.text('Set Parent Workspace'), findsOneWidget);
    expect(find.text('Open in Finder'), findsOneWidget);
    expect(find.text('Open in Project Settings'), findsOneWidget);
    expect(find.text('Open Project Settings'), findsNothing);
    expect(find.text('Copy Path'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Workspace?'), findsNothing);
  });

  testWidgets('workspace context menu sleep confirms and closes every tab', (
    tester,
  ) async {
    final runtime = _FakeTerminalRuntime();
    final registry = EditorSessionRegistry();
    addTearDown(registry.dispose);
    final initialState = _populatedWorkbenchState();
    final workspace = initialState.activeWorkspace!;
    final editorTab = WorkspaceTabRecord(
      id: 'editor-1',
      workspaceId: workspace.id,
      kind: .editor,
      title: 'Notes',
      createdAt: .utc(2026, 5, 22),
      updatedAt: .utc(2026, 5, 22),
      payload: const <String, Object?>{
        workspaceTabFilePathPayloadKey: 'notes.txt',
      },
    );
    registry.register(
      editorTab.id,
      EditorSessionHandle(
        isDirty: () => true,
        save: () async {},
        discard: () async {},
      ),
    );
    await _pumpShell(
      tester,
      state: initialState.copyWith(
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          ...initialState.tabsByWorkspace,
          workspace.id: <WorkspaceTabRecord>[
            ...initialState.tabsFor(workspace.id),
            editorTab,
          ],
        },
      ),
      terminalRuntime: runtime,
      editorSessionRegistry: registry,
      workspaceFolderOpener: WorkspaceFolderOpener(
        processRunner: _NoopProcessRunner(),
        platform: .macos,
        directoryExists: (_) async => true,
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();

    expect(find.text('Sleep Workspace?'), findsOneWidget);
    expect(
      find.textContaining(
        'One editor has unsaved changes that will be discarded.',
      ),
      findsOneWidget,
    );
    expect(runtime.closedWorkspaceIds, isEmpty);
    expect(find.text('Terminal 1'), findsAtLeastNWidgets(1));

    await tester.tap(find.widgetWithText(FilledButton, 'Sleep'));
    await tester.pumpAndSettle();

    expect(runtime.closedWorkspaceIds, <String>['workspace-1']);
    expect(find.text('Terminal 1'), findsNothing);
    expect(find.text('Main'), findsAtLeastNWidgets(1));
  });

  testWidgets('collapsed rail can reopen the sidebar from a project avatar', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Collapse Sidebar'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.collapsed, isTrue);
    expect(find.byTooltip('Expand Sidebar'), findsOneWidget);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.collapsed, isFalse);
    expect(find.byTooltip('Collapse Sidebar'), findsOneWidget);
  });

  testWidgets('sidebar search shows the empty-results state', (tester) async {
    await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.enterText(find.byType(TextField).first, 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No workspaces match "missing"'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    expect(find.text('Main'), findsAtLeastNWidgets(1));
  });

  testWidgets('settings button opens the settings dialog', (tester) async {
    await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Application'), findsWidgets);
  });

  testWidgets('footer add-project button opens the add-project dialog', (
    tester,
  ) async {
    await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add Project'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Project Path'), findsOneWidget);
  });
}
