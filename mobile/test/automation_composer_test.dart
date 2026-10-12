import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/automation_detail_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/automations_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_prompt_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_automation_client.dart';

const Set<String> _withReuse = <String>{
  'automationsV1',
  automationsAuthoringCapability,
  automationTerminalObserveCapability,
  automationReuseCapability,
};

/// Opens the composer for [record] the way the detail screen does.
class const _EditLauncher({required final AutomationRecord record})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showMobileAutomationComposer(
          context,
          hostId: 'host',
          editing: record,
        ),
        child: const Text('Open Composer'),
      ),
    ),
  );
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<FakeAutomationClient> pump(
    WidgetTester tester,
    Widget home, {
    Set<String>? capabilities,
    List<Map<String, Object?>>? automations,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FakeAutomationClient(
      capabilities: capabilities,
      automations: automations,
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileAutomationClientProvider('host')
              .overrideWith((ref) async => client),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
    return client;
  }

  Future<FakeAutomationClient> openNew(
    WidgetTester tester, {
    Set<String>? capabilities,
  }) => pump(
    tester,
    const AutomationsScreen(
      hostId: 'host',
      initialScope: AutomationScope(kind: .workspace, id: 'ws-1'),
      startAuthoring: true,
    ),
    capabilities: capabilities,
  );

  Future<FakeAutomationClient> openEdit(
    WidgetTester tester,
    Map<String, Object?> json, {
    Set<String>? capabilities,
  }) async {
    final client = await pump(
      tester,
      _EditLauncher(record: AutomationRecord.fromJson(json)),
      capabilities: capabilities,
      automations: <Map<String, Object?>>[json],
    );
    await tester.tap(find.text('Open Composer'));
    await settle(tester);
    return client;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await settle(tester);
  }

  Future<void> typePrompt(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(MobileAutomationPromptField),
        matching: find.byType(TextField),
      ),
      text,
    );
    await settle(tester);
  }

  Map<String, Object?> created(FakeAutomationClient client) =>
      client.callsOf('automation.create').single.payload['automation']!
          as Map<String, Object?>;

  testWidgets('a workspace seeds a new tab there and saves it active', (
    tester,
  ) async {
    final client = await openNew(tester);
    expect(find.byType(MobileAutomationComposerScreen), findsOneWidget);
    expect(find.text('New tab in Main'), findsOneWidget);
    expect(find.text('From Context'), findsOneWidget);
    expect(find.text('Codex Daily'), findsOneWidget);
    await typePrompt(tester, 'Review open work');
    expect(find.text('Ready'), findsOneWidget);
    await tapText(tester, 'Create And Activate');
    final sent = created(client);
    expect(sent.containsKey('state'), isFalse);
    expect(sent['originWorkspaceId'], 'ws-1');
    expect(sent['target'], <String, Object?>{
      'freshTab': <String, Object?>{
        'workspaceId': 'ws-1',
        'agentProfileId': 'codex',
      },
    });
    expect(sent.containsKey('reusePolicy'), isFalse);
    expect(find.byType(MobileAutomationComposerScreen), findsNothing);
    expect(find.byType(AutomationDetailScreen), findsNothing);
    expect(find.text('Automation created and active.'), findsOneWidget);
  });

  testWidgets('Save As Draft creates a draft', (tester) async {
    final client = await openNew(tester);
    await typePrompt(tester, 'Review open work');
    await tapText(tester, 'Save As Draft');
    expect(created(client)['state'], 'draft');
  });

  testWidgets('saving without a prompt shows the problem instead', (
    tester,
  ) async {
    final client = await openNew(tester);
    await tapText(tester, 'Create And Activate');
    expect(client.callsOf('automation.create'), isEmpty);
    expect(find.text('Describe what the agent should do.'), findsWidgets);
  });

  testWidgets('editing patches with the expected revision', (tester) async {
    final client = await openEdit(tester, mobileAutomationJson());
    expect(find.text('Edit Automation'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nightly Review'),
      'Morning Review',
    );
    await settle(tester);
    await tapText(tester, 'Save Changes');
    final payload = client.callsOf('automation.patch').single.payload;
    expect(payload['id'], 'nightly');
    expect(payload['expectedRevision'], 2);
    expect((payload['changes']! as Map)['name'], 'Morning Review');
    expect(client.callsOf('automation.resume'), isEmpty);
  });

  testWidgets('a draft saves and activates through resume', (tester) async {
    final client = await openEdit(tester, mobileAutomationJson(state: 'draft'));
    expect(find.text('Save Changes'), findsOneWidget);
    await tapText(tester, 'Save And Activate');
    expect(client.callsOf('automation.patch'), hasLength(1));
    expect(client.callsOf('automation.resume').single.payload, {
      'id': 'nightly',
    });
  });

  testWidgets('Reuse needs the runtime capability', (tester) async {
    await openNew(tester);
    expect(find.text('Reuse'), findsNothing);
  });

  testWidgets('Reuse offers the policies that apply to the destination', (
    tester,
  ) async {
    final client = await openNew(tester, capabilities: _withReuse);
    expect(find.text('New Each Run'), findsOneWidget);
    await tapText(tester, 'New Each Run');
    expect(find.text('Reuse Workspace'), findsNothing);
    await tapText(tester, 'Reuse Conversation');
    expect(find.text('Reuse Conversation'), findsOneWidget);
    await typePrompt(tester, 'Review open work');
    await tapText(tester, 'Create And Activate');
    expect(created(client)['reusePolicy'], 'reuseConversation');
  });

  testWidgets('a conversation destination fixes Reuse and has no agent', (
    tester,
  ) async {
    await openEdit(
      tester,
      mobileAutomationJson(
        extra: const <String, Object?>{
          'target': <String, Object?>{
            'existingTab': <String, Object?>{
              'workspaceId': 'ws-1',
              'tabId': 'tab-1',
              'conversationId': 'conversation-1',
            },
          },
          'reusePolicy': 'reuseConversation',
        },
      ),
      capabilities: _withReuse,
    );
    expect(find.text(automationContinuesConversationLabel), findsOneWidget);
    expect(find.text('Agent'), findsNothing);
    await tester.tap(find.text(automationContinuesConversationLabel));
    await settle(tester);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('Options shows only what applies', (tester) async {
    await openNew(tester);
    await tapText(tester, 'Defaults');
    expect(find.text('SCHEDULE LIMITS'), findsOneWidget);
    expect(find.text('RELIABILITY'), findsOneWidget);
    expect(find.text('WORKSPACE'), findsNothing);
    expect(find.text('Precheck Timeout'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Precheck Command'),
      'test -f ready',
    );
    await settle(tester);
    expect(find.text('Precheck Timeout'), findsOneWidget);
  });

  testWidgets('leaving with changes asks before discarding them', (
    tester,
  ) async {
    final client = await openNew(tester);
    await typePrompt(tester, 'Review open work');
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(find.text('Discard Changes?'), findsOneWidget);
    await tapText(tester, 'Cancel');
    expect(find.byType(MobileAutomationComposerScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    await tapText(tester, 'Discard Changes');
    expect(find.byType(MobileAutomationComposerScreen), findsNothing);
    expect(client.callsOf('automation.create'), isEmpty);
  });

  testWidgets('leaving without changes does not ask', (tester) async {
    await openNew(tester);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(find.text('Discard Changes?'), findsNothing);
    expect(find.byType(MobileAutomationComposerScreen), findsNothing);
  });
}
