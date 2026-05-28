part of 'alera_shell_page_test.dart';

void _registerAleraShellSidebarStateTests() {
  testWidgets('workspace toggle can hide agent rows', (tester) async {
    const prompt = 'Review linked workspace';
    final harness = await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true, linkedActive: true),
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

    expect(find.text(prompt), findsOneWidget);

    final toggles = find.byTooltip('Hide agent runs');
    final workspaceCenter = tester.getCenter(find.text('Feature login').first);
    var toggleIndex = 0;
    var bestDistance = double.infinity;
    final toggleCount = toggles.evaluate().length;
    for (var index = 0; index < toggleCount; index += 1) {
      final distance =
          (tester.getCenter(toggles.at(index)).dy - workspaceCenter.dy).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        toggleIndex = index;
      }
    }

    await tester.tap(toggles.at(toggleIndex));
    await tester.pumpAndSettle();

    expect(
      harness.controller.state.viewPrefs.expandedWorkspaceIds.contains(
        'workspace-2',
      ),
      isFalse,
    );
    expect(find.text(prompt), findsNothing);
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
      find.text('This removes the worktree for "Feature login".'),
      findsOneWidget,
    );
    expect(find.textContaining('deletes branch'), findsNothing);
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

    expect(find.textContaining('Local folder'), findsOneWidget);
  });

  testWidgets('flat workspace grouping shows project chips on workspace rows', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      state: _linkedWorkbenchState(linkedExpanded: true).copyWith(
        viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
          groupBy: WorkbenchGroupBy.none,
          expandedWorkspaceIds: <String>{'workspace-1', 'workspace-2'},
        ),
      ),
    );

    expect(find.byType(AleraChip), findsAtLeastNWidgets(1));
    expect(find.text('Alera'), findsAtLeastNWidgets(1));
  });

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
      find.widgetWithText(TextField, 'Project name'),
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
      find.widgetWithText(TextField, 'Workspace name'),
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
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
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
    await tester.tap(find.text('Remove project'));
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
    await mouse.moveTo(tester.getCenter(find.text(prompt)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close terminal').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.runtime.closedTabIds, <String>['tab-2']);
    expect(events.last.message, 'Bad state: close tab failed');
  });

  testWidgets('hovering sidebar rows updates their highlight state', (
    tester,
  ) async {
    const prompt = 'Review linked workspace';
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
          of: find.text(prompt),
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
    await mouse.moveTo(tester.getCenter(find.text(prompt)));
    await tester.pumpAndSettle();
    expect(decorationOf(terminalContainer).color, AleraTokens.surface);
    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(decorationOf(terminalContainer).color, Colors.transparent);
  });
}
