part of 'alera_shell_page_test.dart';

void _registerAleraShellTerminalRefreshTests() {
  testWidgets('entry refresh includes terminals in the main and right panels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final seeded = _splitWorkbenchState();
    final panel = const WorkspacePanel()
        .applyMainLayout(
          WorkbenchLayout.single(
            workspaceId: 'workspace-1',
            groupId: 'main',
            tabIds: <String>[WorkspacePanel.tabKey('tab-1')],
          ),
        )
        .applyPaneLayout(
          WorkbenchLayout.single(
            workspaceId: 'workspace-1',
            groupId: 'right',
            tabIds: <String>[WorkspacePanel.tabKey('tab-2')],
          ),
        );
    final harness = await _pumpShell(
      tester,
      state: seeded.copyWith(
        viewPrefs: seeded.viewPrefs.copyWith(
          rightSidebarVisible: true,
          workspacePanels: <String, WorkspacePanel>{'workspace-1': panel},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 1);
    expect(_refreshCalls(harness.runtime, 'tab-2'), 1);
    harness.controller.selectWorkspacePanelKey(
      'workspace-1',
      WorkspacePanel.tabKey('tab-1'),
    );
    await tester.pumpAndSettle();
    final mainBefore = _refreshCalls(harness.runtime, 'tab-1');
    harness.controller.selectWorkspacePanelKey(
      'workspace-1',
      WorkspacePanel.tabKey('tab-2'),
    );
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), mainBefore);
    expect(_refreshCalls(harness.runtime, 'tab-2'), 2);
  });

  testWidgets('entry refresh waits for the layout and sleep snapshot', (
    tester,
  ) async {
    final seeded = _populatedWorkbenchState();
    final controller = _RefreshReadyController(seeded);
    final harness = await _pumpShell(
      tester,
      state: seeded,
      controller: controller,
    );
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 0);

    controller.restoreLayout();
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 0);

    controller.restoreSleepSnapshot();
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 1);
  });

  testWidgets('workspace entry refreshes every visible split terminal once', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _splitWorkbenchState());
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 1);
    expect(_refreshCalls(harness.runtime, 'tab-2'), 1);
    expect(harness.runtime.totalFocusRequests, 0);

    harness.agentStatus.setEntries(<String, AgentStatusEntry>{
      'tab-1': _agentStatusEntry(
        terminalSessionId: 'tab-1',
        workspaceId: 'workspace-1',
        tabId: 'tab-1',
        state: .waiting,
      ),
    });
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 1);
    expect(_refreshCalls(harness.runtime, 'tab-2'), 1);
  });

  testWidgets('hidden terminals refresh when their tab is selected', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _stackedWorkbenchState());
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-2'), 1);
    expect(harness.runtime.peekSession('tab-1'), isNull);

    harness.controller.selectWorkspacePanelKey(
      'workspace-1',
      WorkspacePanel.tabKey('tab-1'),
    );
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 1);
    expect(_refreshCalls(harness.runtime, 'tab-2'), 1);
  });

  testWidgets(
    'selecting a terminal in another split refreshes only that terminal',
    (tester) async {
      final harness = await _pumpShell(tester, state: _splitWorkbenchState());
      await tester.pumpAndSettle();
      harness.controller.selectWorkspacePanelKey(
        'workspace-1',
        WorkspacePanel.tabKey('tab-1'),
      );
      await tester.pumpAndSettle();
      final firstBefore = _refreshCalls(harness.runtime, 'tab-1');
      final secondBefore = _refreshCalls(harness.runtime, 'tab-2');

      await tester.tap(find.text('Terminal 2').first);
      await tester.pumpAndSettle();
      expect(_refreshCalls(harness.runtime, 'tab-1'), firstBefore);
      expect(_refreshCalls(harness.runtime, 'tab-2'), secondBefore + 1);

      await tester.tap(find.text('Terminal 1').first);
      await tester.pumpAndSettle();
      expect(_refreshCalls(harness.runtime, 'tab-1'), firstBefore + 1);
      expect(_refreshCalls(harness.runtime, 'tab-2'), secondBefore + 1);

      await tester.tap(find.text('Terminal 1').first);
      await tester.pumpAndSettle();
      expect(_refreshCalls(harness.runtime, 'tab-1'), firstBefore + 1);
    },
  );

  testWidgets(
    'a selected terminal waits for startup and skips refresh if hidden',
    (tester) async {
      final runtime = _FakeTerminalRuntime();
      final start = Completer<void>();
      runtime.startCompleters['tab-1'] = start;
      final harness = await _pumpShell(
        tester,
        state: _stackedWorkbenchState(),
        terminalRuntime: runtime,
      );
      await tester.pumpAndSettle();
      harness.controller.selectWorkspacePanelKey(
        'workspace-1',
        WorkspacePanel.tabKey('tab-1'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(_refreshCalls(runtime, 'tab-1'), 0);

      harness.controller.selectWorkspacePanelKey(
        'workspace-1',
        WorkspacePanel.tabKey('tab-2'),
      );
      await tester.pumpAndSettle();
      start.complete();
      await tester.pumpAndSettle();
      expect(_refreshCalls(runtime, 'tab-1'), 0);
      expect(_refreshCalls(runtime, 'tab-2'), 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning to a workspace refreshes its retained terminal again',
    (tester) async {
      final harness = await _pumpShell(tester, state: _linkedWorkbenchState());
      await tester.pumpAndSettle();
      final first = harness.runtime.peekSession('tab-1');
      await _selectRefreshWorkspace(tester, harness, 'workspace-2');
      expect(_refreshCalls(harness.runtime, 'tab-1'), 1);
      expect(_refreshCalls(harness.runtime, 'tab-2'), 1);

      await _selectRefreshWorkspace(tester, harness, 'workspace-1');
      expect(harness.runtime.peekSession('tab-1'), same(first));
      expect(_refreshCalls(harness.runtime, 'tab-1'), 2);
      expect(_refreshCalls(harness.runtime, 'tab-2'), 1);
    },
  );

  testWidgets('entry refresh waits for asynchronous terminal startup', (
    tester,
  ) async {
    final runtime = _FakeTerminalRuntime();
    final start = Completer<void>();
    runtime.startCompleters['tab-1'] = start;
    await _pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      terminalRuntime: runtime,
    );
    await tester.pump();
    await tester.pump();
    expect(_refreshCalls(runtime, 'tab-1'), 0);

    start.complete();
    await tester.pumpAndSettle();
    expect(_refreshCalls(runtime, 'tab-1'), 1);
    expect(find.byKey(const ValueKey('fake-terminal-tab-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late startup cannot refresh the workspace that was left', (
    tester,
  ) async {
    final runtime = _FakeTerminalRuntime();
    final start = Completer<void>();
    runtime.startCompleters['tab-1'] = start;
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(),
      terminalRuntime: runtime,
    );
    await tester.pump();
    await tester.pump();
    await _selectRefreshWorkspace(tester, harness, 'workspace-2');
    start.complete();
    await tester.pumpAndSettle();
    expect(_refreshCalls(runtime, 'tab-1'), 0);
    expect(_refreshCalls(runtime, 'tab-2'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid workspace changes refresh only the workspace displayed', (
    tester,
  ) async {
    final harness = await _pumpShell(tester, state: _linkedWorkbenchState());
    await tester.pumpAndSettle();
    final controller = harness.controller;
    final project = controller.state.projects.single;
    final workspaces = controller.state.workspacesFor(project.id);
    await controller.selectWorkspace(
      project: project,
      workspace: workspaces.last,
    );
    await tester.pump();
    await controller.selectWorkspace(
      project: project,
      workspace: workspaces.first,
    );
    await tester.pumpAndSettle();
    expect(_refreshCalls(harness.runtime, 'tab-1'), 2);
    expect(_refreshCalls(harness.runtime, 'tab-2'), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the shell cancels a refresh waiting for startup', (
    tester,
  ) async {
    final runtime = _FakeTerminalRuntime();
    final start = Completer<void>();
    runtime.startCompleters['tab-1'] = start;
    await _pumpShell(
      tester,
      state: _populatedWorkbenchState(),
      terminalRuntime: runtime,
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    start.complete();
    await tester.pumpAndSettle();
    expect(_refreshCalls(runtime, 'tab-1'), 0);
    expect(tester.takeException(), isNull);
  });
}

int _refreshCalls(_FakeTerminalRuntime runtime, String tabId) =>
    (runtime.peekSession(
      tabId,
    ) as _FakeTerminalSessionHandle?)?.refreshRenderingCalls ??
    0;

Future<void> _selectRefreshWorkspace(
  WidgetTester tester,
  _ShellPumpHarness harness,
  String workspaceId,
) async {
  final state = harness.controller.state;
  final project = state.projects.single;
  final workspace = state
      .workspacesFor(project.id)
      .singleWhere((workspace) => workspace.id == workspaceId);
  await harness.controller.selectWorkspace(
    project: project,
    workspace: workspace,
  );
  await tester.pumpAndSettle();
}

class _RefreshReadyController(final WorkbenchState seed)
    extends _ShellTestWorkbenchController {
  this
    : super(
        seed.copyWith(
          sleepSnapshotReady: false,
          layoutByWorkspace: const <String, WorkbenchLayout>{},
        ),
      );

  void restoreLayout() {
    state = state.copyWith(layoutByWorkspace: seed.layoutByWorkspace);
  }

  void restoreSleepSnapshot() {
    state = state.copyWith(sleepSnapshotReady: true);
  }
}
