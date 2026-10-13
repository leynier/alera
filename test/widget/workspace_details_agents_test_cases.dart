part of 'workspace_details_overlay_test.dart';

class _Statuses extends AgentStatusController {
  _Statuses(this.seed);
  final Map<String, AgentStatusEntry> seed;
  @override
  Map<String, AgentStatusEntry> build() => seed;
}

WorkspaceTabRecord _agentTab(String id, {String title = 'Terminal'}) =>
    WorkspaceTabRecord(
      id: id,
      workspaceId: 'w',
      title: title,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

AgentStatusEntry _agentStatus(
  String tabId,
  AgentStatusState state, {
  AgentType type = AgentType.codex,
}) => AgentStatusEntry(
  terminalSessionId: tabId,
  workspaceId: 'w',
  tabId: tabId,
  agentType: type,
  state: state,
  prompt: 'Fix it',
  updatedAt: DateTime.utc(2026),
  stateStartedAt: DateTime.utc(2026),
);

Future<_Workbench> _pumpAgents(
  WidgetTester tester,
  Size size,
  Map<String, AgentStatusEntry> statuses, {
  required List<WorkspaceTabRecord> tabs,
  _Runtime? runtime,
}) async {
  await pumpOverlay(
    tester,
    size,
    runtime: runtime,
    workbench: WorkbenchState(
      activeWorkspaceId: 'w',
      tabsByWorkspace: {'w': tabs},
    ),
    overrides: [
      agentStatusControllerProvider.overrideWith(() => _Statuses(statuses)),
    ],
  );
  return ProviderScope.containerOf(
    tester.element(find.byType(WorkspaceDetailsOverlay)),
  ).read(workbenchControllerProvider.notifier) as _Workbench;
}

void _registerWorkspaceDetailsAgentTests() {
  testWidgets('agents get a section and a click focuses their tab', (
    tester,
  ) async {
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
    expect(find.text(agentDisplayName(.codex)), findsOneWidget);
    expect(find.text(agentDisplayName(.grok)), findsOneWidget);
    expect(find.text('Needs Input'), findsOneWidget);
    await tester.tap(find.text(agentDisplayName(.grok)));
    await tester.pumpAndSettle();
    expect(workbench.selectedTabs, ['b']);
    expect(runtime.focused, ['b']);
  });

  testWidgets('a manual tab title names the agent row', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpAgents(
      tester,
      const Size(1000, 900),
      {'a': _agentStatus('a', .done)},
      tabs: [
        WorkspaceTabRecord(
          id: 'a',
          workspaceId: 'w',
          title: 'Fix Login',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          payload: const {workspaceTabManualTitlePayloadKey: true},
        ),
      ],
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

  testWidgets('many agents collapse behind a toggle', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
    await _pumpAgents(
      tester,
      const Size(1000, 1200),
      {for (final id in ids) id: _agentStatus(id, .done)},
      tabs: [for (final id in ids) _agentTab(id)],
    );
    expect(find.text('Show 3 More'), findsOneWidget);
    expect(find.text('Done'), findsNWidgets(3));
    await tester.tap(find.text('Show 3 More'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNWidgets(6));
  });
}
