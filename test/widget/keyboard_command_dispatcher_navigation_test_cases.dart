part of 'keyboard_command_dispatcher_test.dart';

Workspace _workspaceNamed(String id) {
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: id,
    branch: id,
    path: '/tmp/alera/$id',
    createdAt: .utc(2026),
    updatedAt: .utc(2026),
    kind: .linked,
    status: .active,
  );
}

WorkbenchLayout _splitLayout({
  required Workspace workspace,
  required WorkspaceTabRecord leftTab,
  required WorkspaceTabRecord rightTab,
}) {
  return WorkbenchLayout.single(
    workspaceId: workspace.id,
    tabIds: <String>[leftTab.id],
  ).splitWithGroup(
    targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
    zone: .right,
    newGroup: WorkbenchPaneGroup(
      id: 'group-right',
      tabIds: <String>[rightTab.id],
      activeTabId: rightTab.id,
    ),
  );
}

/// Two side-by-side pane scopes whose terminals are the runtime's fake
/// handles, so a dispatched focus command moves the real primary focus.
Widget _twoPaneBody(
  WidgetRef ref, {
  required _FakeTerminalRuntime runtime,
  required Workspace workspace,
  required WorkspaceTabRecord leftTab,
  required WorkspaceTabRecord rightTab,
  required String leftGroupId,
  required String rightGroupId,
  bool autofocusLeft = true,
  Widget? leading,
}) {
  final registry = ref.read(workbenchPaneFocusRegistryProvider);
  return Row(
    children: <Widget>[
      ?leading,
      Expanded(
        child: WorkbenchRegisteredFocusScope(
          registryKey: leftGroupId,
          debugLabel: leftGroupId,
          registry: registry,
          child: runtime
              .sessionFor(workspace: workspace, tab: leftTab)
              .buildView(autofocus: autofocusLeft),
        ),
      ),
      Expanded(
        child: WorkbenchRegisteredFocusScope(
          registryKey: rightGroupId,
          debugLabel: rightGroupId,
          registry: registry,
          child: runtime
              .sessionFor(workspace: workspace, tab: rightTab)
              .buildView(),
        ),
      ),
    ],
  );
}

void _registerKeyboardCommandDispatcherNavigationTests() {
  testWidgets('focusNextPane and focusPreviousPane move focus across panes', (
    tester,
  ) async {
    final project = _project();
    final workspace = _workspace();
    final leftTab = _tab(id: 'tab-left');
    final rightTab = _tab(id: 'tab-right');
    final leftGroupId = WorkbenchLayout.defaultGroupId(workspace.id);
    final layout = _splitLayout(
      workspace: workspace,
      leftTab: leftTab,
      rightTab: rightTab,
    ).setActiveTab(groupId: leftGroupId, tabId: leftTab.id);
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[leftTab, rightTab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: layout},
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
      ),
    );
    final runtime = _FakeTerminalRuntime();
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: runtime,
      body: (context, ref) => _twoPaneBody(
        ref,
        runtime: runtime,
        workspace: workspace,
        leftTab: leftTab,
        rightTab: rightTab,
        leftGroupId: leftGroupId,
        rightGroupId: 'group-right',
      ),
    );
    await tester.pump();
    final left = runtime.sessionFor(
      workspace: workspace,
      tab: leftTab,
    ) as _FakeTerminalSessionHandle;
    final right = runtime.sessionFor(
      workspace: workspace,
      tab: rightTab,
    ) as _FakeTerminalSessionHandle;
    expect(left.focusNode.hasFocus, isTrue);

    final dispatcher = KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    );
    dispatcher.dispatch(.focusNextPane);
    await tester.pump();

    expect(controller.focusedGroupIds, <String>['group-right']);
    expect(right.focusNode.hasFocus, isTrue);
    expect(left.focusNode.hasFocus, isFalse);

    dispatcher.dispatch(.focusPreviousPane);
    await tester.pump();

    expect(controller.focusedGroupIds, <String>['group-right', leftGroupId]);
    expect(left.focusNode.hasFocus, isTrue);
    expect(right.focusNode.hasFocus, isFalse);
  });

  testWidgets(
    'focusNextPane from outside the workbench lands on the active pane',
    (tester) async {
      final project = _project();
      final workspace = _workspace();
      final leftTab = _tab(id: 'tab-left');
      final rightTab = _tab(id: 'tab-right');
      final leftGroupId = WorkbenchLayout.defaultGroupId(workspace.id);
      final layout = _splitLayout(
        workspace: workspace,
        leftTab: leftTab,
        rightTab: rightTab,
      ).setActiveTab(groupId: 'group-right', tabId: rightTab.id);
      final controller = _DispatcherTestWorkbenchController(
        WorkbenchState(
          projects: <Project>[project],
          workspacesByProject: <String, List<Workspace>>{
            project.id: <Workspace>[workspace],
          },
          tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
            workspace.id: <WorkspaceTabRecord>[leftTab, rightTab],
          },
          layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: layout},
          activeProjectId: project.id,
          activeWorkspaceId: workspace.id,
        ),
      );
      final runtime = _FakeTerminalRuntime();
      final sidebarNode = FocusNode(debugLabel: 'sidebar');
      addTearDown(sidebarNode.dispose);
      final harness = await _pumpDispatcherHarness(
        tester,
        controller: controller,
        runtime: runtime,
        body: (context, ref) => _twoPaneBody(
          ref,
          runtime: runtime,
          workspace: workspace,
          leftTab: leftTab,
          rightTab: rightTab,
          leftGroupId: leftGroupId,
          rightGroupId: 'group-right',
          autofocusLeft: false,
          leading: Focus(
            focusNode: sidebarNode,
            autofocus: true,
            child: const SizedBox(width: 40),
          ),
        ),
      );
      await tester.pump();
      expect(sidebarNode.hasFocus, isTrue);

      KeyboardCommandDispatcher(
        ref: harness.ref,
        context: harness.context,
      ).dispatch(.focusNextPane);
      await tester.pump();

      final right = runtime.sessionFor(
        workspace: workspace,
        tab: rightTab,
      ) as _FakeTerminalSessionHandle;
      expect(controller.focusedGroupIds, <String>['group-right']);
      expect(right.focusNode.hasFocus, isTrue);
      expect(sidebarNode.hasFocus, isFalse);
    },
  );

  testWidgets('focusNextPane with one pane keeps a focused descendant', (
    tester,
  ) async {
    final project = _project();
    final workspace = _workspace();
    final tab = _tab(id: 'tab-1');
    final groupId = WorkbenchLayout.defaultGroupId(workspace.id);
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
          workspace.id: <WorkspaceTabRecord>[tab],
        },
        layoutByWorkspace: <String, WorkbenchLayout>{
          workspace.id: WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[tab.id],
          ),
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
      ),
    );
    final runtime = _FakeTerminalRuntime();
    final composerNode = FocusNode(debugLabel: 'composer');
    addTearDown(composerNode.dispose);
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: runtime,
      body: (context, ref) => WorkbenchRegisteredFocusScope(
        registryKey: groupId,
        debugLabel: groupId,
        registry: ref.read(workbenchPaneFocusRegistryProvider),
        child: Column(
          children: <Widget>[
            Expanded(
              child: runtime
                  .sessionFor(workspace: workspace, tab: tab)
                  .buildView(),
            ),
            Focus(
              focusNode: composerNode,
              autofocus: true,
              child: const SizedBox(height: 40),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(composerNode.hasFocus, isTrue);

    KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    ).dispatch(.focusNextPane);
    await tester.pump();

    final session = runtime.sessionFor(
      workspace: workspace,
      tab: tab,
    ) as _FakeTerminalSessionHandle;
    expect(composerNode.hasFocus, isTrue);
    expect(session.requestFocusCalls, 0);
    expect(controller.focusedGroupIds, isEmpty);
  });

  testWidgets('workspace cycling follows the sidebar order and wraps', (
    tester,
  ) async {
    final project = _project();
    final workspaces = <Workspace>[
      _workspaceNamed('ws-a'),
      _workspaceNamed('ws-b'),
      _workspaceNamed('ws-c'),
    ];
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{project.id: workspaces},
        activeProjectId: project.id,
        activeWorkspaceId: 'ws-b',
      ),
    );
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: _FakeTerminalRuntime(),
    );
    final dispatcher = KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    );

    dispatcher.dispatch(.nextWorkspace);
    dispatcher.dispatch(.nextWorkspace);
    dispatcher.dispatch(.previousWorkspace);
    dispatcher.dispatch(.previousWorkspace);

    expect(controller.selectedWorkspaceIds, <String>[
      'ws-c',
      'ws-a',
      'ws-c',
      'ws-b',
    ]);
  });

  testWidgets('context panel commands toggle visibility and select tabs', (
    tester,
  ) async {
    final project = _project();
    final workspace = _workspace();
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
      ),
    );
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: _FakeTerminalRuntime(),
    );
    final dispatcher = KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    );
    expect(
      harness.ref
          .read(workbenchControllerProvider)
          .viewPrefs
          .rightSidebarVisible,
      isTrue,
    );

    dispatcher.dispatch(.toggleContextPanel);
    expect(
      harness.ref
          .read(workbenchControllerProvider)
          .viewPrefs
          .rightSidebarVisible,
      isFalse,
    );

    dispatcher.dispatch(.showSourceControl);
    expect(
      harness.ref
          .read(workbenchControllerProvider)
          .viewPrefs
          .rightSidebarVisible,
      isTrue,
    );
    expect(controller.contextPanelTabs, <WorkbenchContextPanelTab>[.gitDiff]);

    dispatcher.dispatch(.showExplorer);
    expect(controller.contextPanelTabs, <WorkbenchContextPanelTab>[
      .gitDiff,
      .explorer,
    ]);

    dispatcher.dispatch(.toggleContextPanel);
    expect(
      harness.ref
          .read(workbenchControllerProvider)
          .viewPrefs
          .rightSidebarVisible,
      isFalse,
    );
  });

  testWidgets('find and replace in files publish a search reveal request', (
    tester,
  ) async {
    final project = _project();
    final workspace = _workspace();
    final controller = _DispatcherTestWorkbenchController(
      WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
        viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
          rightSidebarVisible: false,
        ),
      ),
    );
    final harness = await _pumpDispatcherHarness(
      tester,
      controller: controller,
      runtime: _FakeTerminalRuntime(),
    );
    final dispatcher = KeyboardCommandDispatcher(
      ref: harness.ref,
      context: harness.context,
    );

    dispatcher.dispatch(.findInFiles);
    final find = harness.ref.read(workspaceSearchRevealProvider);
    expect(find?.replace, isFalse);
    expect(
      harness.ref
          .read(workbenchControllerProvider)
          .viewPrefs
          .rightSidebarVisible,
      isTrue,
    );
    expect(controller.contextPanelTabs, <WorkbenchContextPanelTab>[.search]);

    dispatcher.dispatch(.replaceInFiles);
    final replace = harness.ref.read(workspaceSearchRevealProvider);
    expect(replace?.replace, isTrue);
    expect(replace?.generation, greaterThan(find!.generation));
  });
}
