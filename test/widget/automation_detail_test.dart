import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_dialog.dart';
import 'package:alera/src/features/automations/presentation/detail/automation_runs_tab.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';

const Set<String> _withReuse = <String>{
  automationsAuthoringCapability,
  automationTerminalObserveCapability,
  automationReuseCapability,
};

void main() {
  Future<({ProviderContainer container, FakeAutomationRuntime runtime})> mount(
    WidgetTester tester, {
    required Map<String, Object?> automation,
    List<Map<String, Object?>> runs = const <Map<String, Object?>>[],
    Set<String> capabilities = _withReuse,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = FakeAutomationRuntime(capabilities: capabilities)
      ..automations = <Map<String, Object?>>[automation]
      ..runs = runs;
    final container = automationContainer(runtime);
    addTearDown(container.dispose);
    addTearDown(runtime.dispose);
    container.read(automationsNavigationProvider.notifier)
      ..open()
      ..select('${automation['id']}');
    await tester.pumpWidget(AutomationsTestApp(container: container));
    await tester.pumpAndSettle();
    return (container: container, runtime: runtime);
  }

  testWidgets('facts say when, where, the last run and who created it', (
    tester,
  ) async {
    await mount(
      tester,
      automation: automationJson(
        lastRun: <String, Object?>{'id': 'run-1', 'status': 'failure'},
        createdBy: <String, Object?>{'kind': 'localCli'},
      ),
    );
    for (final label in <String>[
      'Schedule',
      'Destination',
      'Last Run',
      'Created By',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Failed'), findsWidgets);
    expect(find.text('CLI'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('the binding card is hidden for New Each Run', (tester) async {
    await mount(tester, automation: automationJson());
    expect(find.text('Unbind'), findsNothing);
    expect(find.textContaining('Not bound yet'), findsNothing);
  });

  testWidgets('a reusing automation that has not run is not bound yet', (
    tester,
  ) async {
    await mount(
      tester,
      automation: automationJson(reusePolicy: 'reuseWorkspace'),
    );
    expect(find.textContaining('Not bound yet'), findsOneWidget);
  });

  testWidgets('a binding without reuse support stays hidden', (tester) async {
    await mount(
      tester,
      automation: automationJson(reusePolicy: 'reuseWorkspace'),
      capabilities: const <String>{automationsAuthoringCapability},
    );
    expect(find.textContaining('Not bound yet'), findsNothing);
  });

  testWidgets('Unbind asks first, then forgets the binding', (tester) async {
    final f = await mount(
      tester,
      automation: automationJson(
        reusePolicy: 'reuseConversation',
        boundTarget: <String, Object?>{
          'workspaceId': 'ws-1',
          'tabId': 'main-session-1',
          'boundRunId': 'run-1',
        },
        boundTargetSummary: 'Workspace Workflow Delivery · tab Main Terminal',
      ),
    );
    expect(
      find.text('Bound to Workspace Workflow Delivery · tab Main Terminal'),
      findsOneWidget,
    );
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Unbind'));
    await tester.pumpAndSettle();
    expect(find.text('Unbind Workspace?'), findsOneWidget);
    expect(
      find.text(
        'The next run creates a new workspace. The current one is kept.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Unbind').last);
    await tester.pumpAndSettle();
    expect(
      f.runtime.requestsOf('automation.unbind').single.payload,
      <String, Object?>{'id': 'nightly'},
    );
  });

  testWidgets('a binding whose workspace is gone is shown as missing', (
    tester,
  ) async {
    await mount(
      tester,
      automation: automationJson(
        reusePolicy: 'reuseWorkspace',
        boundTarget: <String, Object?>{
          'workspaceId': 'deleted',
          'boundRunId': 'run-1',
        },
        boundTargetSummary: 'Workspace (missing)',
      ),
    );
    expect(find.textContaining('Bound to Workspace (missing)'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Unbind'), findsOneWidget);
  });

  Finder runFilter(String label) => find.descendant(
    of: find.byType(SegmentedButton<AutomationRunFilter>),
    matching: find.text(label),
  );

  testWidgets('runs can be filtered by status', (tester) async {
    await mount(
      tester,
      automation: automationJson(),
      runs: <Map<String, Object?>>[
        automationRunJson(id: 'r1', number: 1, status: 'success'),
        automationRunJson(id: 'r2', number: 2, status: 'failure'),
        automationRunJson(id: 'r3', number: 3, status: 'overlapSkipped'),
      ],
    );
    expect(find.text('#1 · Scheduled run'), findsOneWidget);
    expect(find.text('#2 · Scheduled run'), findsOneWidget);
    await tester.tap(runFilter('Failed'));
    await tester.pumpAndSettle();
    expect(find.text('#2 · Scheduled run'), findsOneWidget);
    expect(find.text('#1 · Scheduled run'), findsNothing);
    await tester.tap(runFilter('Skipped'));
    await tester.pumpAndSettle();
    expect(find.text('#3 · Scheduled run'), findsOneWidget);
    expect(find.text('#2 · Scheduled run'), findsNothing);
  });

  testWidgets('activity lists the audit trail', (tester) async {
    final f = await mount(tester, automation: automationJson());
    f.runtime.details['nightly'] = <String, Object?>{
      'automation': automationJson(),
      'runs': <Object?>[],
      'audit': <Object?>[
        <String, Object?>{
          'action': 'targetUnbound',
          'actor': <String, Object?>{'kind': 'humanDesktop'},
          'details': <String, Object?>{'reason': 'workspaceGone'},
        },
      ],
      'occurrences': <Object?>[],
    };
    f.runtime.emit('automationsChanged', <String, Object?>{
      'automationId': 'nightly',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unbound because the workspace was removed'),
      findsOneWidget,
    );
  });

  testWidgets('Edit opens the composer on the definition', (tester) async {
    await mount(tester, automation: automationJson());
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(AutomationComposerDialog), findsOneWidget);
    expect(find.text('Edit Automation'), findsOneWidget);
  });
}
