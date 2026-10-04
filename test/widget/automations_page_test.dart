import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';

void main() {
  Future<({ProviderContainer container, FakeAutomationRuntime runtime})> mount(
    WidgetTester tester, {
    List<Map<String, Object?>>? automations,
    List<Map<String, Object?>> runs = const <Map<String, Object?>>[],
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = FakeAutomationRuntime()
      ..automations = automations ?? <Map<String, Object?>>[automationJson()]
      ..runs = runs;
    final container = automationContainer(runtime);
    addTearDown(container.dispose);
    addTearDown(runtime.dispose);
    container.read(automationsNavigationProvider.notifier).open();
    await tester.pumpWidget(AutomationsTestApp(container: container));
    await tester.pumpAndSettle();
    return (container: container, runtime: runtime);
  }

  testWidgets('lists schedules and targets in words with no approval step', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Nightly Review'), findsOneWidget);
    expect(find.textContaining('Weekdays at 09:00'), findsOneWidget);
    expect(
      find.textContaining('New tab in Workflow Delivery · Codex Daily'),
      findsOneWidget,
    );
    await tester.tap(find.text('Nightly Review'));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.textContaining('Approve'), findsNothing);
    expect(find.text('Run Now'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('filters stay visible when nothing matches and can be cleared', (
    tester,
  ) async {
    final f = await mount(tester);
    f.container
        .read(automationsNavigationProvider.notifier)
        .setFilters(const AutomationCatalogFilters(search: 'no such thing'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No automations match these filters'),
      findsOneWidget,
    );
    expect(find.text('Search Automations'), findsOneWidget);
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Nightly Review'), findsOneWidget);
  });

  testWidgets('completed definitions stay visible and read-only', (
    tester,
  ) async {
    await mount(
      tester,
      automations: <Map<String, Object?>>[
        automationJson(id: 'once', name: 'Release Notes', state: 'archived'),
      ],
    );
    expect(find.text('Release Notes'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    await tester.tap(find.text('Release Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Run Again'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('workspace scope separates scheduling from run history', (
    tester,
  ) async {
    final f = await mount(
      tester,
      automations: <Map<String, Object?>>[
        automationJson(
          id: 'here',
          name: 'Scheduled In Workspace',
          association: <String, Object?>{
            'workspaceId': 'ws-1',
            'source': 'origin',
          },
        ),
        automationJson(
          id: 'elsewhere',
          name: 'Ran Here Once',
          association: <String, Object?>{
            'workspaceId': 'ws-2',
            'source': 'targetWorkspace',
          },
        ),
      ],
      runs: <Map<String, Object?>>[
        automationRunJson(automationId: 'elsewhere', status: 'success'),
      ],
    );
    f.container
        .read(automationsNavigationProvider.notifier)
        .setScope(const AutomationScope(kind: .workspace, id: 'ws-1'));
    await tester.pumpAndSettle();
    expect(find.text('SCHEDULED HERE'), findsOneWidget);
    expect(find.text('Scheduled In Workspace'), findsOneWidget);
    expect(find.text('Ran Here Once'), findsNothing);
    expect(find.text('RUNS IN THIS WORKSPACE'), findsOneWidget);
    expect(find.textContaining('Ran Here Once ·'), findsOneWidget);
  });

  testWidgets('Run Now reports a skipped run honestly', (tester) async {
    final f = await mount(tester);
    f.runtime.runNowResult = automationRunJson(status: 'overlapSkipped');
    await tester.tap(find.text('Nightly Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Now'));
    await tester.pumpAndSettle();
    expect(
      f.runtime.requestsOf('automation.runNow').single.payload,
      <String, Object?>{'id': 'nightly'},
    );
  });
}
