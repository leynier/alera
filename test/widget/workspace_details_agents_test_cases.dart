part of 'workspace_details_overlay_test.dart';

class _Statuses extends AgentStatusController {
  _Statuses(this.seed);
  final Map<String, AgentStatusEntry> seed;
  @override
  Map<String, AgentStatusEntry> build() => seed;
}

WorkspaceTabRecord _agentTab(String id, {String? title}) => WorkspaceTabRecord(
  id: id,
  workspaceId: 'w',
  title: title ?? 'Terminal',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  payload: title == null
      ? const {}
      : const {workspaceTabManualTitlePayloadKey: true},
);

AgentStatusEntry _agentStatus(
  String tabId,
  AgentStatusState state, {
  AgentType type = AgentType.codex,
  DateTime? at,
}) => AgentStatusEntry(
  terminalSessionId: tabId,
  workspaceId: 'w',
  tabId: tabId,
  agentType: type,
  state: state,
  prompt: 'Fix it',
  updatedAt: at ?? DateTime.utc(2026),
  stateStartedAt: at ?? DateTime.utc(2026),
);

/// Tabs [main] in the main panel; every other tab is in the right panel.
WorkspacePanel _panel(List<String> main) => WorkspacePanel(
  mainLayout: WorkbenchLayout.single(
    workspaceId: 'w',
    tabIds: [for (final id in main) WorkspacePanel.tabKey(id)],
  ),
);

Future<_Workbench> _pumpAgents(
  WidgetTester tester,
  Size size,
  Map<String, AgentStatusEntry> statuses, {
  required List<WorkspaceTabRecord> tabs,
  _Runtime? runtime,
  WorkspacePanel? panel,
  bool expanded = false,
}) async {
  await pumpOverlay(
    tester,
    size,
    runtime: runtime,
    workbench: WorkbenchState(
      activeWorkspaceId: 'w',
      tabsByWorkspace: {'w': tabs},
      viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
        workspacePanels: {'w': ?panel},
        workspaceDetailsAgentsExpandedIds: {if (expanded) 'w'},
      ),
    ),
    overrides: [
      agentStatusControllerProvider.overrideWith(() => _Statuses(statuses)),
    ],
  );
  return ProviderScope.containerOf(
    tester.element(find.byType(WorkspaceDetailsOverlay)),
  ).read(workbenchControllerProvider.notifier) as _Workbench;
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void _registerWorkspaceDetailsAgentTests() {
  testWidgets('agents start collapsed and expand on a click', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = _Runtime();
    final workbench = await _pumpAgents(
      tester,
      const Size(1000, 900),
      {
        'a': _agentStatus('a', .done),
        'b': _agentStatus('b', .waiting, type: .grok),
      },
      tabs: [_agentTab('a'), _agentTab('b'), _agentTab('idle')],
      runtime: runtime,
    );
    expect(find.text('2 Agents'), findsOneWidget);
    expect(find.text(agentDisplayName(.grok)), findsNothing);
    expect(find.byTooltip('Show Agents'), findsOneWidget);

    await tester.tap(find.text('2 Agents'));
    await tester.pumpAndSettle();
    expect(workbench.state.viewPrefs.workspaceDetailsAgentsExpandedIds, {'w'});
    expect(find.text(agentDisplayName(.codex)), findsOneWidget);
    expect(find.text('Needs Input'), findsOneWidget);
    await tester.tap(find.text(agentDisplayName(.grok)));
    await tester.pumpAndSettle();
    expect(workbench.selectedTabs, ['b']);
    expect(runtime.focused, ['b']);

    await tester.tap(find.text('2 Agents'));
    await tester.pumpAndSettle();
    expect(
      workbench.state.viewPrefs.workspaceDetailsAgentsExpandedIds,
      isEmpty,
    );
    expect(find.text(agentDisplayName(.grok)), findsNothing);
  });

  testWidgets('a manual tab title names a single agent', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpAgents(
      tester,
      const Size(1000, 900),
      {'a': _agentStatus('a', .done)},
      tabs: [_agentTab('a', title: 'Fix Login')],
    );
    expect(find.text('Fix Login'), findsOneWidget);
  });

  testWidgets('a workspace without agents has no agents section', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpAgents(
      tester,
      const Size(1000, 900),
      const {},
      tabs: [_agentTab('idle')],
    );
    expect(find.byType(AleraWorkspaceDetailsSection), findsNothing);
  });

  testWidgets('main panel agents come first, each panel by activity', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
    final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
    await _pumpAgents(
      tester,
      const Size(1000, 1400),
      {
        'a': _agentStatus('a', .done, at: ago(1)),
        'b': _agentStatus('b', .waiting, at: ago(3)),
        'c': _agentStatus('c', .done, at: now),
        'd': _agentStatus('d', .done, at: ago(5)),
        'e': _agentStatus('e', .blocked, at: ago(9)),
        'f': _agentStatus('f', .waiting, at: ago(120)),
      },
      tabs: [for (final id in ids) _agentTab(id, title: 'Agent $id')],
      panel: _panel(['a', 'b', 'c']),
      expanded: true,
    );
    final order = [for (final id in ids) (id, _top(tester, 'Agent $id'))]
      ..sort((x, y) => x.$2.compareTo(y.$2));
    expect(
      [for (final entry in order) entry.$1],
      ['b', 'c', 'a', 'e', 'd', 'f'],
    );
    expect(
      find.byKey(const ValueKey('workspace-details-agents-main')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-details-agents-right')),
      findsOneWidget,
    );
  });

  testWidgets('right panel agents collapse while main ones stay open', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workbench = await _pumpAgents(
      tester,
      const Size(1000, 1200),
      {'a': _agentStatus('a', .done), 'b': _agentStatus('b', .done)},
      tabs: [
        _agentTab('a', title: 'Main'),
        _agentTab('b', title: 'Side'),
      ],
      panel: _panel(['a']),
      expanded: true,
    );
    expect(find.text('Side'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('workspace-details-agents-right')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Side'), findsNothing);
    expect(find.byTooltip('Show Right Panel Agents'), findsOneWidget);
    expect(workbench.state.viewPrefs.workspaceDetailsAgentGroupsCollapsed, {
      'w:right',
    });
  });

  testWidgets('agents in one panel get no dividers', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpAgents(
      tester,
      const Size(1000, 900),
      {'a': _agentStatus('a', .done), 'b': _agentStatus('b', .done)},
      tabs: [
        _agentTab('a', title: 'One'),
        _agentTab('b', title: 'Two'),
      ],
      expanded: true,
    );
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-details-agents-main')),
      findsNothing,
    );
  });

  testWidgets('a short card lists the agents in a menu', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpAgents(
      tester,
      const Size(1000, 290),
      {
        'a': _agentStatus('a', .done),
        'b': _agentStatus('b', .waiting, type: .grok),
      },
      tabs: [_agentTab('a'), _agentTab('b')],
      expanded: true,
    );
    expect(find.text('2 Agents'), findsOneWidget);
    expect(find.text(agentDisplayName(.grok)), findsNothing);
    await tester.tap(find.text('2 Agents'));
    await tester.pumpAndSettle();
    expect(find.text(agentDisplayName(.grok)), findsOneWidget);
    expect(find.text(agentDisplayName(.codex)), findsOneWidget);
  });
}
