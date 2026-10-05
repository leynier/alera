import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';

void main() {
  Future<({ProviderContainer container, FakeAutomationRuntime runtime})> open(
    WidgetTester tester, {
    AutomationAuthoringRequest request = const AutomationAuthoringRequest(),
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = FakeAutomationRuntime();
    final container = automationContainer(runtime);
    addTearDown(container.dispose);
    addTearDown(runtime.dispose);
    await tester.pumpWidget(AutomationsTestApp(container: container));
    container
        .read(automationsNavigationProvider.notifier)
        .startAuthoring(request);
    await tester.pumpAndSettle();
    return (container: container, runtime: runtime);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  Future<void> reachWhere(WidgetTester tester) async {
    await tester.enterText(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(TextField))
          .first,
      'Review open work',
    );
    await next(tester);
    await next(tester);
    expect(find.text('Where Should It Run?'), findsOneWidget);
  }

  testWidgets('the target type is never preselected, even from a workspace', (
    tester,
  ) async {
    await open(
      tester,
      request: const AutomationAuthoringRequest(originWorkspaceId: 'ws-1'),
    );
    await reachWhere(tester);
    expect(find.byIcon(AleraIcons.radioOn), findsNothing);
    expect(
      find.byIcon(AleraIcons.radioOff),
      findsNWidgets(AutomationTargetType.values.length),
    );
    expect(
      find.textContaining('Created from Workflow Delivery'),
      findsOneWidget,
    );
    await next(tester);
    expect(find.text('Where Should It Run?'), findsOneWidget);
    expect(find.text('Choose where the automation runs.'), findsOneWidget);
  });

  testWidgets(
    'context fills a chosen type, and Create sends an active definition',
    (tester) async {
      final f = await open(
        tester,
        request: const AutomationAuthoringRequest(originWorkspaceId: 'ws-1'),
      );
      await reachWhere(tester);
      await tester.tap(find.text('New Agent Tab In A Workspace'));
      await tester.pumpAndSettle();
      expect(find.text('From Context'), findsNWidgets(2));
      await next(tester);
      expect(find.text('Create Automation'), findsOneWidget);
      expect(find.text('Save As Draft'), findsOneWidget);
      expect(find.text('Advanced'), findsOneWidget);
      await tester.tap(find.text('Create Automation'));
      await tester.pumpAndSettle();
      final sent =
          f.runtime
                  .requestsOf('automation.create')
                  .single
                  .payload['automation']!
              as Map<String, Object?>;
      expect(sent.containsKey('state'), isFalse);
      expect(sent['originWorkspaceId'], 'ws-1');
      expect(sent['misfirePolicy'], 'skip');
      expect(sent['target'], <String, Object?>{
        'freshTab': <String, Object?>{
          'workspaceId': 'ws-1',
          'agentProfileId': 'codex',
        },
      });
      expect(
        f.container.read(automationsNavigationProvider).selectedId,
        'created',
      );
    },
  );

  testWidgets('Save As Draft is the only way to create a draft', (
    tester,
  ) async {
    final f = await open(
      tester,
      request: const AutomationAuthoringRequest(originWorkspaceId: 'ws-1'),
    );
    await reachWhere(tester);
    await tester.tap(find.text('New Agent Tab In A Workspace'));
    await tester.pumpAndSettle();
    await next(tester);
    await tester.tap(find.text('Save As Draft'));
    await tester.pumpAndSettle();
    final sent =
        f.runtime.requestsOf('automation.create').single.payload['automation']!
            as Map<String, Object?>;
    expect(sent['state'], 'draft');
  });

  testWidgets('advanced numbers show the runtime limit inline', (tester) async {
    await open(
      tester,
      request: const AutomationAuthoringRequest(originWorkspaceId: 'ws-1'),
    );
    await reachWhere(tester);
    await tester.tap(find.text('New Agent Tab In A Workspace'));
    await tester.pumpAndSettle();
    await next(tester);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    final field = find.ancestor(
      of: find.text('Circuit Failure Threshold (1-10 failures)'),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '50');
    await tester.pumpAndSettle();
    expect(find.text('Use 1 to 10 failures.'), findsOneWidget);
  });
}
