import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/presentation/automation_detail_view.dart';
import 'package:alera/src/features/automations/presentation/catalog/automation_catalog_row.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';

void main() {
  Future<({ProviderContainer container, FakeAutomationRuntime runtime})> mount(
    WidgetTester tester, {
    List<Map<String, Object?>>? automations,
    List<Map<String, Object?>> runs = const <Map<String, Object?>>[],
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
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

  Finder rowOf(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byType(AutomationCatalogRow),
  );

  bool actionsVisible(WidgetTester tester, String name) => tester
      .widget<Visibility>(
        find.descendant(of: rowOf(name), matching: find.byType(Visibility)),
      )
      .visible;

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
    expect(find.textContaining('Approve'), findsNothing);
    expect(find.text('Run Now'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('each group has one header, sorted rows, and collapses', (
    tester,
  ) async {
    final f = await mount(
      tester,
      automations: <Map<String, Object?>>[
        automationJson(id: 'a', name: 'Alpha', projectId: 'project-1'),
        automationJson(id: 'b', name: 'Beta', projectId: 'project-2'),
        automationJson(id: 'c', name: 'Gamma', projectId: 'project-1'),
      ],
    );
    expect(find.text('Alera'), findsOneWidget);
    expect(find.text('Other Project'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Gamma')).dy,
      lessThan(tester.getTopLeft(find.text('Other Project')).dy),
    );
    await tester.tap(find.text('Alera'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(
      f.container.read(automationsNavigationProvider).collapsedGroups,
      <String>{'project-1'},
    );
  });

  testWidgets('status buckets filter the catalog', (tester) async {
    await mount(
      tester,
      automations: <Map<String, Object?>>[
        automationJson(id: 'a', name: 'Running Daily'),
        automationJson(id: 'p', name: 'On Hold', state: 'paused'),
      ],
    );
    await tester.tap(find.text('Paused').first);
    await tester.pumpAndSettle();
    expect(find.text('On Hold'), findsOneWidget);
    expect(find.text('Running Daily'), findsNothing);
  });

  testWidgets('row actions appear on hover in space the row reserves', (
    tester,
  ) async {
    final f = await mount(tester);
    expect(actionsVisible(tester, 'Nightly Review'), isFalse);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(rowOf('Nightly Review')));
    await tester.pumpAndSettle();
    expect(actionsVisible(tester, 'Nightly Review'), isTrue);
    await tester.tap(
      find.descendant(
        of: rowOf('Nightly Review'),
        matching: find.byTooltip('Run Now'),
      ),
    );
    await tester.pumpAndSettle();
    expect(f.runtime.requestsOf('automation.runNow'), hasLength(1));
  });

  testWidgets('the narrow layout returns from the detail to the list', (
    tester,
  ) async {
    final f = await mount(tester, size: const Size(700, 900));
    await tester.tap(find.text('Nightly Review'));
    await tester.pumpAndSettle();
    expect(find.byType(AutomationDetailView), findsOneWidget);
    await tester.tap(find.byTooltip('Back To Automations'));
    await tester.pumpAndSettle();
    expect(find.byType(AutomationDetailView), findsNothing);
    expect(find.text('Nightly Review'), findsOneWidget);
    expect(f.container.read(automationsNavigationProvider).selectedId, isNull);
  });

  testWidgets('a banner leads to the definitions that need attention', (
    tester,
  ) async {
    final f = await mount(
      tester,
      automations: <Map<String, Object?>>[
        automationJson(),
        automationJson(
          id: 'stuck',
          name: 'Stuck Review',
          attention: <String, Object?>{
            'code': 'profileMissing',
            'message': 'Its agent profile was removed.',
          },
        ),
      ],
    );
    expect(find.text('1 automation needs attention.'), findsOneWidget);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(
      f.container.read(automationsNavigationProvider).filters.bucket,
      AutomationBucket.needsAttention,
    );
    expect(find.text('1 automation needs attention.'), findsNothing);
    expect(find.text('Nightly Review'), findsNothing);
    expect(find.text('Stuck Review'), findsOneWidget);
  });

  testWidgets('Move To Trash asks first', (tester) async {
    final f = await mount(tester);
    await tester.tap(find.text('Nightly Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move To Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Move To Trash?'), findsOneWidget);
    expect(f.runtime.requestsOf('automation.trash'), isEmpty);
    await tester.tap(find.text('Move To Trash').last);
    await tester.pumpAndSettle();
    expect(f.runtime.requestsOf('automation.trash'), hasLength(1));
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
    await tester.tap(find.text('Clear Filters').last);
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
    expect(find.text('Workspace: Workflow Delivery'), findsOneWidget);
    expect(find.text('Scheduled In Workspace'), findsOneWidget);
    expect(find.text('Ran Here Once'), findsNothing);
    expect(find.text('RUNS IN THIS WORKSPACE'), findsOneWidget);
    expect(find.textContaining('Ran Here Once ·'), findsOneWidget);
  });

  testWidgets('Run Now sends no overrides', (tester) async {
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
