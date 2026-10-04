import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/automations/presentation/automation_run_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';
import '../support/run_board_widget_harness.dart';

void main() {
  Future<({FakeAutomationRuntime runtime, BoardTestWorkbench workbench})> mount(
    WidgetTester tester, {
    required Map<String, Object?> run,
    Set<String>? capabilities,
    List<AutomationAttemptRecord> attempts = const <AutomationAttemptRecord>[],
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = FakeAutomationRuntime(
      capabilities:
          capabilities ??
          <String>{
            automationsAuthoringCapability,
            automationTerminalObserveCapability,
          },
    );
    final workbench = BoardTestWorkbench();
    final container = automationContainer(runtime, workbench: workbench);
    addTearDown(container.dispose);
    addTearDown(runtime.dispose);
    final record = AutomationRunRecord.fromJson(run);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AutomationRunPanel(
                automation: AutomationRecord.fromJson(automationJson()),
                run: record,
                runs: <AutomationRunRecord>[record],
                attempts: attempts,
                onSelectRun: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await container.read(automationRuntimeCapabilitiesProvider.future);
    await tester.pumpAndSettle();
    return (runtime: runtime, workbench: workbench);
  }

  testWidgets('Watch Terminal opens the tab without taking the run over', (
    tester,
  ) async {
    final f = await mount(tester, run: automationRunJson());
    expect(find.text('Take Over · Stops Automatic Recovery'), findsOneWidget);
    await tester.tap(find.text('Watch Terminal'));
    await tester.pumpAndSettle();
    expect(f.workbench.actions, <String>[
      'workspace:ws-1',
      'terminal:main-session-1',
    ]);
    expect(f.runtime.requestsOf('automation.takeOver'), isEmpty);
  });

  testWidgets('Take Over is an explicit action with no extra dialog', (
    tester,
  ) async {
    final f = await mount(tester, run: automationRunJson());
    await tester.tap(find.text('Take Over · Stops Automatic Recovery'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      f.runtime.requestsOf('automation.takeOver').single.payload,
      <String, Object?>{'runId': 'run-1'},
    );
  });

  testWidgets('older runtimes label the attach as a takeover', (tester) async {
    await mount(
      tester,
      run: automationRunJson(),
      capabilities: <String>{automationsAuthoringCapability},
    );
    expect(find.text('Open And Take Over'), findsOneWidget);
    expect(find.text('Watch Terminal'), findsNothing);
  });

  testWidgets('recovery is shown and can be stopped', (tester) async {
    final f = await mount(
      tester,
      run: automationRunJson(
        recovery: <String, Object?>{
          'status': 'retryingWithContext',
          'attempt': 2,
          'maxAttempts': 3,
        },
      ),
    );
    expect(
      find.textContaining('Retrying With Context · Attempt 2 Of 3'),
      findsWidgets,
    );
    await tester.tap(find.text('Stop Recovery'));
    await tester.pumpAndSettle();
    expect(f.runtime.requestsOf('automation.cancel'), hasLength(1));
  });

  testWidgets('Run Again continues from the run as a new run', (tester) async {
    final f = await mount(
      tester,
      run: automationRunJson(
        status: 'failure',
        recovery: <String, Object?>{'status': 'exhausted'},
      ),
    );
    expect(find.textContaining('Recovery used every attempt'), findsOneWidget);
    await tester.tap(find.text('Run Again'));
    await tester.pumpAndSettle();
    expect(find.text('Start Fresh'), findsOneWidget);
    await tester.tap(find.text('Continue From Run #1'));
    await tester.pumpAndSettle();
    expect(
      f.runtime.requestsOf('automation.runNow').single.payload,
      <String, Object?>{'id': 'nightly', 'continueFromRunId': 'run-1'},
    );
    expect(f.workbench.actions, isEmpty);
  });

  testWidgets('a timed-out run keeps its owner reservation visible', (
    tester,
  ) async {
    await mount(
      tester,
      run: <String, Object?>{
        ...automationRunJson(status: 'timeout'),
        'ownerReserved': true,
      },
    );
    expect(find.textContaining('Owner Reserved'), findsOneWidget);
  });

  testWidgets('each recovery attempt can be watched on its own tab', (
    tester,
  ) async {
    final f = await mount(
      tester,
      run: automationRunJson(),
      attempts: <AutomationAttemptRecord>[
        AutomationAttemptRecord.fromJson(<String, Object?>{
          'id': 'a1',
          'runId': 'run-1',
          'number': 1,
          'status': 'failure',
          'launchKind': 'initial',
          'tabId': 'main-session-1',
        }),
      ],
    );
    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    expect(f.workbench.actions, contains('terminal:main-session-1'));
    expect(f.runtime.requestsOf('automation.takeOver'), isEmpty);
  });
}
