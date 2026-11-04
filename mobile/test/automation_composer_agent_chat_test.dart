import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_agent_chats.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_agent_chat_fields.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_prompt_field.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_automation_client.dart';

const Set<String> _withAgentChat = <String>{
  'automationsV1',
  automationsAuthoringCapability,
  automationTerminalObserveCapability,
  automationAgentChatTargetCapability,
};

const List<AgentChatProviderInstance> _providers = <AgentChatProviderInstance>[
  AgentChatProviderInstance(
    id: 'claude',
    provider: 'claudeAgent',
    label: 'Claude',
    runtimeModes: <AgentChatRuntimeMode>[
      AgentChatRuntimeMode.approvalRequired,
      AgentChatRuntimeMode.auto,
    ],
    models: <AgentChatModelOption>[
      AgentChatModelOption(
        id: 'opus',
        label: 'Opus',
        reasoningEfforts: <String>['low', 'high'],
      ),
    ],
  ),
];

final List<AgentChatSummary> _chats = <AgentChatSummary>[
  AgentChatSummary(
    chatId: 'chat-7',
    workspaceId: 'ws-1',
    title: 'Deploy watch',
    provider: 'codex',
    providerInstanceId: 'codex',
    status: AgentChatSessionStatus.ready,
    updatedAt: DateTime.utc(2026, 11),
  ),
];

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<FakeAutomationClient> openNew(
    WidgetTester tester, {
    Set<String> capabilities = _withAgentChat,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FakeAutomationClient(capabilities: capabilities);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileAutomationClientProvider('host')
              .overrideWith((ref) async => client),
          agentChatProvidersProvider.overrideWith(
            (ref, args) async => _providers,
          ),
          mobileAutomationAgentChatsProvider.overrideWith(
            (ref, args) async =>
                args.$2 == 'ws-1' ? _chats : const <AgentChatSummary>[],
          ),
        ],
        child: const MaterialApp(
          home: ActivityScreen(
            hostId: 'host',
            initialSection: ActivitySection.automations,
            automationScope: AutomationScope(kind: .workspace, id: 'ws-1'),
            startAutomationAuthoring: true,
          ),
        ),
      ),
    );
    await settle(tester);
    return client;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
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

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(450, 20));
    await settle(tester);
  }

  Map<String, Object?> created(FakeAutomationClient client) =>
      client.callsOf('automation.create').single.payload['automation']!
          as Map<String, Object?>;

  Future<void> chooseAgentChat(WidgetTester tester) async {
    await tap(tester, find.text('New tab in Main'));
    await tap(tester, find.textContaining('existing or new each run').first);
  }

  testWidgets('a new chat each run saves its agent, effort and ceiling', (
    tester,
  ) async {
    final client = await openNew(tester);
    await typePrompt(tester, 'Check the deploy');
    await chooseAgentChat(tester);
    expect(find.text(mobileAutomationNewChatEachRunLabel), findsOneWidget);
    expect(find.text('Full Access'), findsOneWidget);

    await tap(tester, find.text('Choose Agent'));
    await tap(tester, find.text('Opus').last);
    // Claude offers no Full Access, so the ceiling drops to its most access.
    expect(find.text('Full Access'), findsNothing);
    expect(find.text('Auto'), findsOneWidget);
    await tap(tester, find.text('Model Default'));
    await tap(tester, find.text('High').last);
    await closeSheet(tester);

    await tap(tester, find.text('Create And Activate'));
    expect(created(client)['target'], <String, Object?>{
      'agentChat': <String, Object?>{
        'workspaceId': 'ws-1',
        'runtimeModeCeiling': 'auto',
        'provider': 'claudeAgent',
        'providerInstanceId': 'claude',
        'model': 'opus',
        'reasoningEffort': 'high',
      },
    });
  });

  testWidgets('an existing chat of the workspace takes every run', (
    tester,
  ) async {
    final client = await openNew(tester);
    await typePrompt(tester, 'Check the deploy');
    await chooseAgentChat(tester);
    await tap(tester, find.text(mobileAutomationNewChatEachRunLabel));
    await tap(tester, find.text('Deploy watch').last);
    expect(find.text('Choose Agent'), findsNothing);
    await closeSheet(tester);
    await tap(tester, find.text('Create And Activate'));
    expect(created(client)['target'], <String, Object?>{
      'agentChat': <String, Object?>{
        'chatId': 'chat-7',
        'workspaceId': 'ws-1',
        'runtimeModeCeiling': 'full-access',
      },
    });
  });

  testWidgets('an interval runs in minutes, hours or days from now', (
    tester,
  ) async {
    final client = await openNew(tester);
    await typePrompt(tester, 'Check the deploy');
    await tap(tester, find.textContaining('Weekdays at 09:00').first);
    await tap(tester, find.text('Weekdays At'));
    await tap(tester, find.text('Fixed Interval').last);
    final count = find.descendant(
      of: find.byKey(const ValueKey<String>('automation-interval-count')),
      matching: find.byType(TextField),
    );
    await tester.enterText(count, '0');
    await settle(tester);
    expect(find.text('Repeat at most once a minute.'), findsOneWidget);
    await tester.enterText(count, '30');
    await settle(tester);
    await tap(tester, find.text('Hours').last);
    await tap(tester, find.text('Minutes').last);
    expect(find.text('Every 30 minutes'), findsWidgets);
    await closeSheet(tester);

    final before = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    await tap(tester, find.text('Create And Activate'));
    final interval =
        (created(client)['schedule']! as Map<String, Object?>)['interval']!
            as Map<String, Object?>;
    expect(interval['everySeconds'], 1800);
    expect(
      DateTime.parse(interval['anchor']! as String).isAfter(before),
      isTrue,
    );
  });

  testWidgets('an older runtime offers neither agent chats nor intervals', (
    tester,
  ) async {
    await openNew(
      tester,
      capabilities: const <String>{
        'automationsV1',
        automationsAuthoringCapability,
        automationTerminalObserveCapability,
      },
    );
    await tap(tester, find.text('New tab in Main'));
    expect(find.textContaining('existing or new each run'), findsNothing);
    await closeSheet(tester);
    await tap(tester, find.textContaining('Weekdays at 09:00').first);
    await tap(tester, find.text('Weekdays At'));
    expect(find.text('Fixed Interval'), findsNothing);
  });
}
