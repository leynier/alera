import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/automation_detail_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_sheet.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
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

const Set<String> _reuseCapabilities = <String>{
  'automationsV1',
  automationsAuthoringCapability,
  automationTerminalObserveCapability,
  automationReuseCapability,
};

void main() {
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('lists automations in words, one header per project', (
    tester,
  ) async {
    tallView(tester);
    final client = FakeAutomationClient(
      automations: <Map<String, Object?>>[
        mobileAutomationJson(extra: const {'projectId': 'project-1'}),
        mobileAutomationJson(
          id: 'weekly',
          name: 'Weekly Cleanup',
          extra: const {'projectId': 'project-1'},
        ),
        mobileAutomationJson(id: 'loose', name: 'Loose Check'),
      ],
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.automations,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ALERA'), findsOneWidget);
    expect(find.text('OTHERS'), findsOneWidget);
    expect(find.text('Nightly Review'), findsOneWidget);
    expect(find.text('Weekly Cleanup'), findsOneWidget);
    expect(find.text('Loose Check'), findsOneWidget);
    expect(find.textContaining('Weekdays at 09:00'), findsNWidgets(3));
    expect(find.textContaining('New tab in Main'), findsNWidgets(3));
    expect(find.textContaining('Approve'), findsNothing);
  });

  testWidgets('bucket chips filter the list', (tester) async {
    tallView(tester);
    final client = FakeAutomationClient(
      automations: <Map<String, Object?>>[
        mobileAutomationJson(),
        mobileAutomationJson(id: 'later', name: 'Later Idea', state: 'draft'),
      ],
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.automations,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Later Idea'), findsOneWidget);
    await tapText(tester, 'Drafts');
    expect(find.text('Later Idea'), findsOneWidget);
    expect(find.text('Nightly Review'), findsNothing);
    await tapText(tester, 'All');
    expect(find.text('Nightly Review'), findsOneWidget);
  });

  testWidgets('a blocked automation raises the attention banner', (
    tester,
  ) async {
    tallView(tester);
    final client = FakeAutomationClient(
      automations: <Map<String, Object?>>[
        mobileAutomationJson(state: 'blocked'),
        mobileAutomationJson(id: 'fine', name: 'Fine One'),
      ],
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.automations,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 automation needs attention.'), findsOneWidget);
    expect(find.text('Needs Attention · 1'), findsOneWidget);
    await tapText(tester, 'Show');
    expect(find.text('Fine One'), findsNothing);
    expect(find.text('Nightly Review'), findsOneWidget);
  });

  testWidgets('an empty host offers New Automation', (tester) async {
    tallView(tester);
    final client = FakeAutomationClient(
      automations: const <Map<String, Object?>>[],
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.automations,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No Automations Yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'New Automation'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(MobileAutomationComposerScreen), findsOneWidget);
  });

  testWidgets('a filtered empty list offers Clear Filters', (tester) async {
    tallView(tester);
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.automations,
          automationScope: AutomationScope(kind: .workspace, id: 'elsewhere'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No automations match these filters.'), findsOneWidget);
    await tapText(tester, 'Clear Filters');
    expect(find.text('Nightly Review'), findsOneWidget);
  });

  testWidgets('the binding card unbinds only after confirming', (tester) async {
    tallView(tester);
    final client = FakeAutomationClient(
      capabilities: _reuseCapabilities,
      automations: <Map<String, Object?>>[
        mobileAutomationJson(
          extra: const <String, Object?>{
            'reusePolicy': 'reuseWorkspace',
            'boundTarget': <String, Object?>{
              'workspaceId': 'ws-1',
              'boundRunId': 'run-1',
            },
            'boundTargetSummary': 'Main',
          },
        ),
      ],
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const AutomationDetailScreen(hostId: 'host', automationId: 'nightly'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reuse Workspace'), findsOneWidget);
    expect(find.text('Bound to Main'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    await tapText(tester, 'Unbind');
    expect(find.text('Unbind Workspace?'), findsOneWidget);
    await tapText(tester, 'Cancel');
    expect(client.callsOf('automation.unbind'), isEmpty);
    await tapText(tester, 'Unbind');
    await tapText(tester, 'Unbind');
    expect(client.callsOf('automation.unbind').single.payload, {
      'id': 'nightly',
    });
  });

  testWidgets('an unbound reusing automation says it is not bound yet', (
    tester,
  ) async {
    tallView(tester);
    final client = FakeAutomationClient(
      capabilities: _reuseCapabilities,
      automations: <Map<String, Object?>>[
        mobileAutomationJson(
          extra: const <String, Object?>{'reusePolicy': 'reuseConversation'},
        ),
      ],
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const AutomationDetailScreen(hostId: 'host', automationId: 'nightly'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Not bound yet.'), findsOneWidget);
    expect(find.text('Unbind'), findsNothing);
  });

  testWidgets('detail shows facts, no binding card without reuse', (
    tester,
  ) async {
    tallView(tester);
    final client = FakeAutomationClient(
      automations: <Map<String, Object?>>[
        mobileAutomationJson(
          extra: const <String, Object?>{'reusePolicy': 'reuseWorkspace'},
        ),
      ],
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const AutomationDetailScreen(hostId: 'host', automationId: 'nightly'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('No runs yet'), findsOneWidget);
    expect(find.text('Reuse Workspace'), findsNothing);
    expect(find.text('Runs'), findsOneWidget);
    await tapText(tester, 'Activity');
    expect(find.text('No activity yet.'), findsOneWidget);
  });

  testWidgets('Move To Trash asks first', (tester) async {
    tallView(tester);
    final client = FakeAutomationClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const AutomationDetailScreen(hostId: 'host', automationId: 'nightly'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Actions'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Move To Trash');
    expect(find.text('Move To Trash?'), findsOneWidget);
    expect(client.callsOf('automation.trash'), isEmpty);
    await tapText(tester, 'Move To Trash');
    expect(client.callsOf('automation.trash').single.payload, {
      'id': 'nightly',
    });
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
