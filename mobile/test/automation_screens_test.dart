import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/automations_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_automation_client.dart';

Widget _app(FakeAutomationClient client, Widget child) => ProviderScope(
  overrides: [
    mobileAutomationClientProvider('host').overrideWith((ref) async => client),
  ],
  child: MaterialApp(home: child),
);

Map<String, Object?> _run({
  String status = 'dispatched',
  bool takenOver = false,
}) => <String, Object?>{
  'id': 'run-1',
  'automationId': 'nightly',
  'number': 1,
  'status': status,
  'trigger': 'scheduled',
  'workspaceId': 'ws-1',
  'tabId': 'tab-1',
  'takenOver': takenOver,
};

void main() {
  testWidgets('lists automations in words with no approval controls', (
    tester,
  ) async {
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(client, const AutomationsScreen(hostId: 'host')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nightly Review'), findsOneWidget);
    expect(find.textContaining('Weekdays at 09:00'), findsOneWidget);
    expect(
      find.textContaining('New tab in Main · Codex Daily'),
      findsOneWidget,
    );
    expect(find.textContaining('Approve'), findsNothing);
    expect(find.text('New Automation'), findsOneWidget);
  });

  testWidgets('a filtered empty list offers Clear Filters', (tester) async {
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const AutomationsScreen(
          hostId: 'host',
          initialScope: AutomationScope(kind: .workspace, id: 'elsewhere'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No automations match these filters.'), findsOneWidget);
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Nightly Review'), findsOneWidget);
  });

  testWidgets('authoring never preselects the execution target', (
    tester,
  ) async {
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const AutomationsScreen(
          hostId: 'host',
          initialScope: AutomationScope(kind: .workspace, id: 'ws-1'),
          startAuthoring: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Review open work');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Where Should It Run?'), findsOneWidget);
    expect(find.byIcon(AleraIcons.check), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Choose where the automation runs.'), findsOneWidget);
    await tester.tap(find.text('New Agent Tab In A Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('From Context'), findsNWidgets(2));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Automation'));
    await tester.pumpAndSettle();
    final sent =
        client.callsOf('automation.create').single.payload['automation']!
            as Map<String, Object?>;
    expect(sent.containsKey('state'), isFalse);
    expect(sent['originWorkspaceId'], 'ws-1');
  });

  testWidgets('a run offers Watch Terminal and an explicit Take Over', (
    tester,
  ) async {
    final client = FakeAutomationClient()
      ..runs = <Map<String, Object?>>[_run()];
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const Scaffold(
          body: MobileAutomationRunSheet(
            hostId: 'host',
            automationId: 'nightly',
            runId: 'run-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Watch Terminal'), findsOneWidget);
    await tester.tap(find.text('Take Over · Stops Automatic Recovery'));
    await tester.pumpAndSettle();
    expect(client.callsOf('automation.takeOver').single.payload, {
      'runId': 'run-1',
    });
  });

  testWidgets('older runtimes label the attach as a takeover', (tester) async {
    final client = FakeAutomationClient(
      capabilities: <String>{'automationsV1', automationsAuthoringCapability},
    )..runs = <Map<String, Object?>>[_run()];
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const Scaffold(
          body: MobileAutomationRunSheet(
            hostId: 'host',
            automationId: 'nightly',
            runId: 'run-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open And Take Over'), findsOneWidget);
    expect(find.text('Watch Terminal'), findsNothing);
  });

  testWidgets('Run Again continues from a finished run as a new run', (
    tester,
  ) async {
    final client = FakeAutomationClient()
      ..runs = <Map<String, Object?>>[_run(status: 'failure')];
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const Scaffold(
          body: MobileAutomationRunSheet(
            hostId: 'host',
            automationId: 'nightly',
            runId: 'run-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue From Run #1'));
    await tester.pumpAndSettle();
    expect(client.callsOf('automation.runNow').single.payload, {
      'id': 'nightly',
      'continueFromRunId': 'run-1',
    });
  });
}
