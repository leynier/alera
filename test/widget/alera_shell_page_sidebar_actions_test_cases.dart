part of 'alera_shell_page_test.dart';

void _registerAleraShellSidebarActionTests() {
  testWidgets(
    'new-workspace toolbar button opens the create-workspace dialog',
    (tester) async {
      await _pumpShell(tester, state: _populatedWorkbenchState());

      await tester.tap(find.byTooltip('New workspace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.widgetWithText(FilledButton, 'Create workspace'),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping a workspace row selects that workspace', (tester) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tap(find.text('Feature login'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.activeWorkspaceId, 'workspace-2');
  });

  testWidgets('workspace context menu shows folder-open failures as a toast', (
    tester,
  ) async {
    final opener = WorkspaceFolderOpener(
      processRunner: _NoopProcessRunner(),
      platform: WorkspaceFolderPlatform.macos,
      directoryExists: (_) async => false,
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
    await tester.tap(find.text('Open in Finder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Main'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('project context menu renames the project', (tester) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Project name'),
      '  Renamed Alera  ',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.controller.state.projects.single.name, 'Renamed Alera');
  });

  testWidgets('workspace context menu renames the workspace', (tester) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace name'),
      '  Backend API  ',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.controller.state.workspacesFor('project-1').last.name,
      'Backend API',
    );
  });

  testWidgets('workspace context menu copies the workspace path', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tapAt(
      tester.getCenter(find.text('Main').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy path'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copiedText, '/repo/alera');
  });

  testWidgets('sidebar agent rows can switch workspaces and request focus', (
    tester,
  ) async {
    const prompt = 'Review linked workspace';
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-2': _agentStatusEntry(
          terminalSessionId: 'tab-2',
          workspaceId: 'workspace-2',
          tabId: 'tab-2',
          state: AgentStatusState.waiting,
          prompt: prompt,
        ),
      },
    );

    await tester.tap(find.text(prompt));
    await tester.pumpAndSettle();

    expect(harness.controller.state.activeWorkspaceId, 'workspace-2');
    expect(
      harness.controller.state.activeTabIdByWorkspace['workspace-2'],
      'tab-2',
    );
    expect(harness.runtime.focusedTabIds, contains('tab-2'));
  });

  testWidgets('closing a sidebar agent row closes the runtime tab', (
    tester,
  ) async {
    const prompt = 'Review linked workspace';
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-2': _agentStatusEntry(
          terminalSessionId: 'tab-2',
          workspaceId: 'workspace-2',
          tabId: 'tab-2',
          state: AgentStatusState.waiting,
          prompt: prompt,
        ),
      },
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text(prompt)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close terminal').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(harness.controller.state.tabsFor('workspace-2'), isEmpty);
    expect(harness.controller.state.activeWorkspaceId, 'workspace-1');
    expect(harness.runtime.focusedTabIds, isNot(contains('tab-2')));
    expect(find.text(prompt), findsNothing);
  });

  testWidgets('linked workspace removal closes runtime and removes the row', (
    tester,
  ) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.runtime.closedWorkspaceIds, <String>['workspace-2']);
    expect(
      harness.controller.state.workspacesFor('project-1').map((w) => w.id),
      <String>['workspace-1'],
    );
    expect(find.text('Feature login'), findsNothing);
  });

  testWidgets('project removal closes every workspace runtime', (tester) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      harness.runtime.closedWorkspaceIds,
      containsAll(<String>['workspace-1', 'workspace-2']),
    );
    expect(harness.controller.state.projects, isEmpty);
    expect(find.text('No projects yet'), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'shell shows a toast when the workbench state contains an error',
    (tester) async {
      final events = <AleraToastData>[];
      final subscription = AleraToast.stream.listen(events.add);
      addTearDown(subscription.cancel);

      await _pumpShell(
        tester,
        state: _populatedWorkbenchState().copyWith(error: 'Workspace failed'),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(events, isNotEmpty);
      expect(events.last.message, 'Workspace failed');
      expect(events.last.tone, AleraToastTone.error);
    },
  );

  testWidgets('clicking a tab activates it in the shell state bridge', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _stackedWorkbenchState());

    await tester.tap(find.text('Terminal 1').first);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.activeTabIdByWorkspace['workspace-1'],
      'tab-1',
    );
  });

  testWidgets('closing a tab from its context menu updates shell state', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _stackedWorkbenchState());

    await tester.tapAt(
      tester.getCenter(find.text('Terminal 2').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(
      harness.controller.state.tabsFor('workspace-1').map((tab) => tab.id),
      <String>['tab-1'],
    );
  });

  testWidgets('renaming a tab from its context menu updates shell state', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _stackedWorkbenchState());

    await tester.tapAt(
      tester.getCenter(find.text('Terminal 1').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change title'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Terminal title'),
      '  Renamed tab  ',
    );
    await tester.tap(find.text('Change title').last);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.tabsFor('workspace-1').first.title,
      'Renamed tab',
    );
  });

  testWidgets('pane split actions focus the new terminal session', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Pane actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split right'));
    await tester.pumpAndSettle();

    expect(harness.runtime.totalFocusRequests, 1);
    expect(harness.controller.state.tabsFor('workspace-1'), hasLength(2));
  });

  testWidgets('closing a split merges the layout in the shell bridge', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _splitWorkbenchState());

    await tester.tap(find.byTooltip('Pane actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close split'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.layoutFor('workspace-1')!.paneGroupIds,
      hasLength(1),
    );
  });

  testWidgets('dragging the shell split handle updates the layout ratio', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _splitWorkbenchState());

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(WorkspaceWorkbenchView)),
    );
    await gesture.moveBy(const Offset(48, 0));
    await gesture.up();
    await tester.pump();

    expect(
      harness.controller.state.layoutFor('workspace-1')!.root.ratio!,
      greaterThan(0.5),
    );
  });

  testWidgets('collapsed sidebar settings button still opens the dialog', (
    tester,
  ) async {
    await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('General'), findsWidgets);
  });

  testWidgets('collapsed brand row can expand the sidebar', (tester) async {
    final harness = await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand sidebar'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.collapsed, isFalse);
    expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
  });

  testWidgets('project header quick action opens create workspace dialog', (
    tester,
  ) async {
    await _pumpShell(tester, state: _populatedWorkbenchState());

    await tester.tap(find.byTooltip('New workspace in this project'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.widgetWithText(FilledButton, 'Create workspace'),
      findsOneWidget,
    );
  });

  testWidgets('project context menu can open the create workspace dialog', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workspace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.widgetWithText(FilledButton, 'Create workspace'),
      findsOneWidget,
    );
  });
}
