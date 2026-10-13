part of 'workspace_details_overlay_test.dart';

class _Catalog extends AutomationCatalog {
  _Catalog(this.records);
  final List<AutomationRecord> records;
  @override
  Future<List<AutomationRecord>> build() async => records;
}

AutomationRecord _automation(
  String id,
  String name, {
  String workspaceId = 'w',
  String state = 'active',
  Map<String, Object?>? lastRun,
}) => AutomationRecord.fromJson(
  automationJson(
    id: id,
    name: name,
    state: state,
    association: <String, Object?>{
      'workspaceId': workspaceId,
      'source': 'origin',
    },
    lastRun: lastRun,
  ),
);

Future<ProviderContainer> _pumpAutomations(
  WidgetTester tester,
  List<AutomationRecord> records,
) async {
  await pumpOverlay(tester, const Size(1000, 900), automations: records);
  return ProviderScope.containerOf(
    tester.element(find.byType(WorkspaceDetailsOverlay)),
  );
}

void _registerWorkspaceDetailsAutomationTests() {
  testWidgets('workspace automations get a row with the latest run', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await _pumpAutomations(tester, [
      _automation(
        'nightly',
        'Nightly Review',
        lastRun: <String, Object?>{
          'id': 'run-1',
          'status': 'success',
          'finishedAt': DateTime.now().toUtc().toIso8601String(),
        },
      ),
      _automation('weekly', 'Weekly Cleanup'),
      _automation('done', 'Finished', state: 'archived'),
      _automation('elsewhere', 'Other Workspace', workspaceId: 'x'),
    ]);
    expect(find.text('2 Automations'), findsOneWidget);
    expect(find.textContaining('Succeeded'), findsOneWidget);
    await tester.tap(find.text('2 Automations'));
    await tester.pumpAndSettle();
    final location = container.read(activityNavigationProvider).automations;
    expect(location.scope.kind, AutomationScopeKind.workspace);
    expect(location.scope.id, 'w');
  });

  testWidgets('the automations menu opens one automation', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await _pumpAutomations(tester, [
      _automation('nightly', 'Nightly Review'),
    ]);
    expect(find.text('No runs yet'), findsOneWidget);
    await tester.tap(find.byTooltip('Nightly Review Options'));
    await tester.pumpAndSettle();
    expect(find.text('New Automation Here'), findsOneWidget);
    await tester.tap(find.text('Nightly Review').last);
    await tester.pumpAndSettle();
    expect(
      container.read(activityNavigationProvider).automations.selectedId,
      'nightly',
    );
  });

  testWidgets('a run in progress outranks an older finished run', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpAutomations(tester, [
      _automation(
        'nightly',
        'Nightly Review',
        lastRun: <String, Object?>{
          'id': 'run-1',
          'status': 'success',
          'finishedAt': DateTime.now().toUtc().toIso8601String(),
        },
      ),
      _automation(
        'weekly',
        'Weekly Cleanup',
        lastRun: <String, Object?>{'id': 'run-2', 'status': 'dispatched'},
      ),
    ]);
    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('Succeeded'), findsNothing);
    expect(find.text('No runs yet'), findsNothing);
  });

  testWidgets('essential density reaches automations from the options menu', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(
      tester,
      const Size(1000, 300),
      automations: [_automation('nightly', 'Nightly Review')],
    );
    expect(find.text('No runs yet'), findsNothing);
    await tester.tap(find.byTooltip('Workspace Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nightly Review').last);
    await tester.pumpAndSettle();
    expect(find.text('New Automation Here'), findsOneWidget);
  });

  testWidgets('a workspace without automations has no automations row', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpAutomations(tester, [
      _automation('elsewhere', 'Other Workspace', workspaceId: 'x'),
    ]);
    expect(find.byIcon(AleraIcons.checks), findsNothing);
  });
}
