import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/automations/application/automation_agent_chats.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_agent_chat_fields.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_dialog.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_prompt_editor.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';

const Set<String> _withAgentChat = <String>{
  automationsAuthoringCapability,
  automationTerminalObserveCapability,
  automationAgentChatTargetCapability,
};

const List<AgentChatProviderInstance> _providers = <AgentChatProviderInstance>[
  AgentChatProviderInstance(
    id: 'codex',
    provider: 'codex',
    label: 'Codex',
    runtimeModes: AgentChatRuntimeMode.values,
    models: <AgentChatModelOption>[
      AgentChatModelOption(
        id: 'gpt-5.5',
        label: 'GPT-5.5',
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

typedef _Composer = ({
  ProviderContainer container,
  FakeAutomationRuntime runtime,
});

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<_Composer> open(
    WidgetTester tester, {
    AutomationAuthoringRequest request = const AutomationAuthoringRequest(
      originWorkspaceId: 'ws-1',
    ),
    Set<String> capabilities = _withAgentChat,
    List<Map<String, Object?>> automations = const <Map<String, Object?>>[],
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = FakeAutomationRuntime(capabilities: capabilities)
      ..automations = automations;
    final container = automationContainer(
      runtime,
      overrides: [
        agentChatProviderCatalogProvider.overrideWith(
          (ref, workspaceId) async => _providers,
        ),
        automationAgentChatsProvider.overrideWith(
          (ref, workspaceId) async =>
              workspaceId == 'ws-1' ? _chats : const <AgentChatSummary>[],
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(runtime.dispose);
    await tester.pumpWidget(AutomationsTestApp(container: container));
    container.read(activityNavigationProvider.notifier).openAutomations();
    await settle(tester);
    container.read(activityNavigationProvider.notifier).startAuthoring(request);
    await settle(tester);
    expect(find.byType(AutomationComposerDialog), findsOneWidget);
    return (container: container, runtime: runtime);
  }

  Future<void> typePrompt(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AutomationPromptEditor),
        matching: find.byType(TextField),
      ),
      text,
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> closePopover(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
  }

  Map<String, Object?> created(FakeAutomationRuntime runtime) =>
      runtime.requestsOf('automation.create').single.payload['automation']!
          as Map<String, Object?>;

  Future<void> searchDestinations(WidgetTester tester, String query) async {
    await tap(tester, find.text('New tab in Workflow Delivery'));
    await tester.enterText(
      find.ancestor(
        of: find.text('Search Workspaces, Projects And Agents'),
        matching: find.byType(TextField),
      ),
      query,
    );
    await settle(tester);
  }

  Future<void> chooseAgentChat(WidgetTester tester) async {
    await searchDestinations(tester, 'existing or new');
    expect(find.text('AGENT CHAT'), findsOneWidget);
    await tap(tester, find.textContaining('existing or new each run').first);
  }

  testWidgets('a new chat each run saves its agent, effort and ceiling', (
    tester,
  ) async {
    final f = await open(tester);
    await typePrompt(tester, 'Check the deploy');
    await chooseAgentChat(tester);
    expect(find.text(automationNewChatEachRunLabel), findsOneWidget);
    // The most access a chat can have until the person lowers it.
    expect(find.text('Full Access'), findsOneWidget);

    await tap(tester, find.text('Choose Agent'));
    await tap(tester, find.text('GPT-5.5').last);
    await tap(tester, find.text('Model Default'));
    await tap(tester, find.text('High').last);
    await tap(tester, find.text('Full Access'));
    await tap(tester, find.text('Auto').last);
    await closePopover(tester);
    expect(
      find.text('New chat in Workflow Delivery for each run'),
      findsOneWidget,
    );

    await tap(tester, find.text('Create And Activate'));
    expect(created(f.runtime)['target'], <String, Object?>{
      'agentChat': <String, Object?>{
        'workspaceId': 'ws-1',
        'runtimeModeCeiling': 'auto',
        'provider': 'codex',
        'providerInstanceId': 'codex',
        'model': 'gpt-5.5',
        'reasoningEffort': 'high',
      },
    });
  });

  testWidgets('an existing chat of the workspace takes every run', (
    tester,
  ) async {
    final f = await open(tester);
    await typePrompt(tester, 'Check the deploy');
    await chooseAgentChat(tester);
    await tap(tester, find.text(automationNewChatEachRunLabel));
    await tap(tester, find.text('Deploy watch').last);
    expect(find.text('Choose Agent'), findsNothing);
    await closePopover(tester);
    await tap(tester, find.text('Create And Activate'));
    expect(created(f.runtime)['target'], <String, Object?>{
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
    final f = await open(tester);
    await typePrompt(tester, 'Check the deploy');
    await tap(tester, find.textContaining('Weekdays at 09:00'));
    await tap(tester, find.text('Weekdays At'));
    await tap(tester, find.text('Fixed Interval').last);
    final count = find.descendant(
      of: find.byKey(const ValueKey<String>('automation-interval-count')),
      matching: find.byType(TextField),
    );
    await tester.enterText(count, '0');
    await settle(tester);
    expect(find.text('Repeat at most once a minute.'), findsOneWidget);
    await tester.enterText(count, '2');
    await settle(tester);
    // The unit stays while the count is retyped.
    await tap(tester, find.text('Hours').last);
    await tap(tester, find.text('Days').last);
    expect(find.text('Every 2 days'), findsWidgets);
    await closePopover(tester);

    final before = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    await tap(tester, find.text('Create And Activate'));
    final interval =
        (created(f.runtime)['schedule']! as Map<String, Object?>)['interval']!
            as Map<String, Object?>;
    expect(interval['everySeconds'], 2 * 86400);
    expect(
      DateTime.parse(interval['anchor']! as String).isAfter(before),
      isTrue,
    );
  });

  testWidgets('editing keeps the stored anchor until the interval changes', (
    tester,
  ) async {
    final stored = automationJson(
      target: <String, Object?>{
        'agentChat': <String, Object?>{
          'workspaceId': 'ws-1',
          'chatId': 'chat-7',
          'runtimeModeCeiling': 'full-access',
        },
      },
    );
    stored['schedule'] = <String, Object?>{
      'interval': <String, Object?>{
        'everySeconds': 3 * 3600,
        'anchor': '2026-11-01T08:00:00Z',
      },
    };
    final f = await open(
      tester,
      request: const AutomationAuthoringRequest(editId: 'nightly'),
      automations: <Map<String, Object?>>[stored],
    );
    await typePrompt(tester, 'Check the deploy twice');
    await tap(tester, find.text('Save Changes'));
    final changes =
        f.runtime.requestsOf('automation.patch').single.payload['changes']!
            as Map<String, Object?>;
    expect(changes['schedule'], <String, Object?>{
      'interval': <String, Object?>{
        'everySeconds': 3 * 3600,
        'anchor': '2026-11-01T08:00:00.000Z',
      },
    });
  });

  testWidgets('an older runtime offers neither agent chats nor intervals', (
    tester,
  ) async {
    await open(
      tester,
      capabilities: const <String>{
        automationsAuthoringCapability,
        automationTerminalObserveCapability,
      },
    );
    await searchDestinations(tester, 'existing or new');
    expect(find.text('AGENT CHAT'), findsNothing);
    await closePopover(tester);
    await tap(tester, find.textContaining('Weekdays at 09:00'));
    await tap(tester, find.text('Weekdays At'));
    expect(find.text('Fixed Interval'), findsNothing);
  });
}
