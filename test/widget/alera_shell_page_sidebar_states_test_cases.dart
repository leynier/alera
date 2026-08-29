part of 'alera_shell_page_test.dart';

void _registerAleraShellSidebarStateTests() {
  testWidgets('inactive workspaces with terminal tabs show active dots', (
    tester,
  ) async {
    await _pumpShell(tester, state: _linkedWorkbenchState());

    final dots = tester
        .widgetList<AleraStatusDot>(
          find.descendant(
            of: find.byType(ProjectWorkbenchSidebar),
            matching: find.byType(AleraStatusDot),
          ),
        )
        .toList();

    expect(dots, hasLength(2));
    expect(dots.map((dot) => dot.active), <bool>[true, true]);
  });

  testWidgets('inactive workspaces without terminal tabs keep muted dots', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState();
    final state = seeded.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        'workspace-1': seeded.tabsFor('workspace-1'),
        'workspace-2': const <WorkspaceTabRecord>[],
      },
    );

    await _pumpShell(tester, state: state);

    final dots = tester
        .widgetList<AleraStatusDot>(
          find.descendant(
            of: find.byType(ProjectWorkbenchSidebar),
            matching: find.byType(AleraStatusDot),
          ),
        )
        .toList();

    expect(dots, hasLength(2));
    expect(dots.map((dot) => dot.active), <bool>[true, false]);
  });

  testWidgets('workspace agent pill toggles expanded rows', (tester) async {
    final harness = await _pumpShell(
      tester,
      state: _stackedWorkbenchState(),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-1': _agentStatusEntry(
          terminalSessionId: 'tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          state: AgentStatusState.waiting,
          lastAssistantMessage: 'Needs input',
        ),
        'tab-2': _agentStatusEntry(
          terminalSessionId: 'tab-2',
          workspaceId: 'workspace-1',
          tabId: 'tab-2',
          state: AgentStatusState.waiting,
          lastAssistantMessage: 'Ready to continue',
        ),
      },
    );

    expect(find.byType(WorkspaceAgentCompactSummary), findsOneWidget);
    expect(find.text('Needs input'), findsNothing);
    expect(find.text('Ready to continue'), findsNothing);

    await tester.tap(find.byTooltip('Show Agent Runs'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds.contains(
        'workspace-1',
      ),
      isTrue,
    );
    expect(find.byType(WorkspaceAgentCompactSummary), findsOneWidget);
    expect(find.text('Needs input'), findsOneWidget);
    expect(find.text('Ready to continue'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide Agent Runs'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds.contains(
        'workspace-1',
      ),
      isFalse,
    );
    expect(find.text('Needs input'), findsNothing);
    expect(find.text('Ready to continue'), findsNothing);
  });

  testWidgets('selecting a workspace does not expand agent rows', (
    tester,
  ) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(),
      agentStatuses: <String, AgentStatusEntry>{
        'tab-2': _agentStatusEntry(
          terminalSessionId: 'tab-2',
          workspaceId: 'workspace-2',
          tabId: 'tab-2',
          state: AgentStatusState.waiting,
        ),
      },
    );

    await tester.tap(find.text('Feature login'));
    await tester.pumpAndSettle();

    expect(harness.controller.state.activeWorkspaceId, 'workspace-2');
    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds.contains(
        'workspace-2',
      ),
      isFalse,
    );
  });

  testWidgets('workspace removal dialog omits branch details when blank', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState(linkedExpanded: true);
    final workspaces = seeded.workspacesFor('project-1');
    final branchlessState = seeded.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        'project-1': <Workspace>[
          workspaces.first,
          workspaces.last.copyWith(branch: ''),
        ],
      },
    );

    await _pumpShell(tester, state: branchlessState);

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('This removes the worktree for "Feature login".'),
      findsOneWidget,
    );
    expect(find.textContaining('deletes branch'), findsNothing);
  });

  testWidgets('workspace branch metadata omits base branch labels', (
    tester,
  ) async {
    await _pumpShell(tester, state: _linkedWorkbenchState());

    expect(find.byIcon(AleraIcons.gitBranch), findsNWidgets(2));
    expect(find.byKey(const Key('workspace-tray-branch')), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'feature/login',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'main',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Base:'), findsNothing);
  });

  testWidgets('project header tap toggles the collapsed project state', (
    tester,
  ) async {
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true),
    );

    await tester.tap(find.text('Alera').last);
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.collapsedProjectIds,
      contains('project-1'),
    );
  });

  testWidgets('folder projects describe their workspaces as local folders', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 5, 22);
    final project = Project(
      id: 'project-folder',
      name: 'Notes',
      repoPath: '/repo/notes',
      createdAt: now,
      updatedAt: now,
      kind: ProjectKind.folder,
    );
    final workspace = Workspace(
      id: 'workspace-folder',
      projectId: project.id,
      name: 'Notes',
      branch: '',
      path: project.repoPath,
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceKind.main,
      status: WorkspaceStatus.active,
    );

    await _pumpShell(
      tester,
      state: WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
        bootstrapped: true,
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'Local Folder',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(find.byTooltip('Source Control'), findsNothing);
  });

  testWidgets(
    'flat workspace grouping shows project folder icons with tooltips',
    (tester) async {
      await _pumpShell(
        tester,
        state: _linkedWorkbenchState(linkedExpanded: true).copyWith(
          viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
            groupBy: WorkbenchGroupBy.none,
            expandedWorkspaceIds: <String>{'workspace-1', 'workspace-2'},
          ),
        ),
      );

      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Feature login'), findsOneWidget);
      expect(find.byKey(const Key('workspace-tray-project')), findsNWidgets(2));
      expect(find.byIcon(AleraIcons.folderSpecial), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == 'Alera',
        ),
        findsNWidgets(2),
      );
    },
  );

  testWidgets('workspace rows show tags and children in the icon tray', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState(linkedExpanded: true);
    final workspaces = seeded.workspacesFor('project-1');
    final parent = workspaces.first.copyWith(childCount: 1);
    final child = workspaces.last.copyWith(
      parentWorkspaceId: parent.id,
      tagNames: const <String>['frontend', 'review', 'qa', 'ux'],
    );

    await _pumpShell(
      tester,
      state: seeded.copyWith(
        workspacesByProject: <String, List<Workspace>>{
          'project-1': <Workspace>[parent, child],
        },
      ),
    );

    expect(find.text('#frontend'), findsNothing);
    expect(find.byKey(const Key('workspace-tray-tags')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && widget.message == 'frontend, review, qa, ux',
      ),
      findsOneWidget,
    );
    expect(find.text('Child'), findsNothing);
    expect(find.text('1 Child'), findsNothing);
    expect(find.text('1 child'), findsNothing);
    expect(find.byTooltip('Remove Workspace'), findsNothing);
    expect(find.byKey(const Key('workspace-tray-children')), findsOneWidget);
    expect(find.byIcon(AleraIcons.workspaceChildren), findsOneWidget);
    expect(find.byTooltip('Hide Child Workspaces'), findsOneWidget);
  });

  testWidgets('collapse all closes projects, child workspaces, and agents', (
    tester,
  ) async {
    final seeded = _linkedWorkbenchState(linkedExpanded: true);
    final workspaces = seeded.workspacesFor('project-1');
    final parent = workspaces.first.copyWith(childCount: 1);
    final child = workspaces.last.copyWith(parentWorkspaceId: parent.id);
    final state = seeded.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        'project-1': <Workspace>[parent, child],
      },
      viewPrefs: seeded.viewPrefs.copyWith(
        expandedWorkspaceIds: <String>{parent.id, child.id},
      ),
    );
    final harness = await _pumpShell(tester, state: state);

    await tester.tap(find.byTooltip('Collapse All'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.collapsedProjectIds,
      contains('project-1'),
    );
    expect(
      harness.controller.state.viewPrefs.collapsedParentWorkspaceIds,
      contains(parent.id),
    );
    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(parent.id)),
    );
    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds,
      isNot(contains(child.id)),
    );

    await tester.tap(find.byTooltip('Expand All'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.collapsedProjectIds,
      isNot(contains('project-1')),
    );
    expect(
      harness.controller.state.viewPrefs.collapsedParentWorkspaceIds,
      isNot(contains(parent.id)),
    );
    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds,
      containsAll(<String>[parent.id, child.id]),
    );
  });

  testWidgets(
    'expand all opens collapsed projects despite hidden agent state',
    (tester) async {
      final seeded = _linkedWorkbenchState(linkedExpanded: true);
      final workspaces = seeded.workspacesFor('project-1');
      final parent = workspaces.first.copyWith(childCount: 1);
      final child = workspaces.last.copyWith(parentWorkspaceId: parent.id);
      final state = seeded.copyWith(
        workspacesByProject: <String, List<Workspace>>{
          'project-1': <Workspace>[parent, child],
        },
        viewPrefs: seeded.viewPrefs.copyWith(
          collapsedProjectIds: <String>{'project-1'},
          collapsedParentWorkspaceIds: <String>{parent.id},
          expandedWorkspaceIds: <String>{parent.id, child.id},
        ),
      );
      final harness = await _pumpShell(tester, state: state);

      await tester.tap(find.byTooltip('Expand All'));
      await tester.pumpAndSettle();

      expect(
        harness.controller.state.viewPrefs.collapsedProjectIds,
        isNot(contains('project-1')),
      );
      expect(
        harness.controller.state.viewPrefs.collapsedParentWorkspaceIds,
        isNot(contains(parent.id)),
      );
      expect(
        harness.controller.state.viewPrefs.expandedWorkspaceIds,
        containsAll(<String>[parent.id, child.id]),
      );
    },
  );

  testWidgets('project rename failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await _pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        renameProjectFailure: StateError('rename failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Project Name'),
      'New',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: rename failed');
  });

  testWidgets('workspace rename failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await _pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        renameWorkspaceFailure: StateError('rename workspace failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Workspace Name'),
      'Renamed',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: rename workspace failed');
  });

  testWidgets('workspace removal failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await _pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        deleteWorkspaceFailure: StateError('delete workspace failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Feature login').first),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clean Up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: delete workspace failed');
  });

  testWidgets('project removal failures surface an error toast event', (
    tester,
  ) async {
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    await _pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        removeProjectFailure: StateError('remove project failed'),
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.text('Alera').last),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(events.last.message, 'Bad state: remove project failed');
  });

  testWidgets('sidebar agent close failures surface an error toast event', (
    tester,
  ) async {
    const prompt = 'Review linked workspace';
    const description = 'Codex · Waiting for input';
    final events = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(events.add);
    addTearDown(subscription.cancel);
    final state = _linkedWorkbenchState(linkedExpanded: true);

    final harness = await _pumpShell(
      tester,
      state: state,
      controller: _ShellTestWorkbenchController(
        state,
        closeWorkspaceTabFailure: StateError('close tab failed'),
      ),
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
    await mouse.moveTo(tester.getCenter(find.text(description)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close Terminal').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A failed close keeps the terminal alive: the runtime handle is disposed
    // by the controller only after the tab record was actually removed.
    expect(harness.runtime.closedTabIds, isEmpty);
    expect(events.last.message, 'Bad state: close tab failed');
  });

  testWidgets('hovering sidebar rows updates their highlight state', (
    tester,
  ) async {
    const prompt = 'Review linked workspace';
    const description = 'Codex · Waiting for input';
    await _pumpShell(
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

    final projectContainer = find
        .ancestor(
          of: find.text('Alera').last,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final workspaceContainer = find
        .ancestor(
          of: find.text('Feature login').first,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final terminalContainer = find
        .ancestor(
          of: find.text(description),
          matching: find.byType(AnimatedContainer),
        )
        .first;

    BoxDecoration decorationOf(Finder finder) {
      return tester.widget<AnimatedContainer>(finder).decoration!
          as BoxDecoration;
    }

    expect(decorationOf(projectContainer).color, Colors.transparent);
    await mouse.moveTo(tester.getCenter(find.text('Alera').last));
    await tester.pumpAndSettle();
    expect(decorationOf(projectContainer).color, AleraTokens.surface);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(decorationOf(projectContainer).color, Colors.transparent);

    expect(decorationOf(workspaceContainer).color, Colors.transparent);
    await mouse.moveTo(tester.getCenter(find.text('Feature login').first));
    await tester.pumpAndSettle();
    expect(decorationOf(workspaceContainer).color, AleraTokens.surface);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(decorationOf(workspaceContainer).color, Colors.transparent);

    expect(decorationOf(terminalContainer).color, Colors.transparent);
    await mouse.moveTo(tester.getCenter(find.text(description)));
    await tester.pumpAndSettle();
    expect(decorationOf(terminalContainer).color, AleraTokens.surface);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(decorationOf(terminalContainer).color, Colors.transparent);
  });
}
