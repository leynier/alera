import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

Map<String, Object?> _queued(String id, String text) => <String, Object?>{
  'queueId': id,
  'clientMessageId': 'm-$id',
  'text': text,
  'createdAt': '2026-10-25T10:01:00Z',
};

Future<FakeAgentChatClient> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = FakeAgentChatClient(
    capabilities: <String>{
      AgentChatWire.capability,
      AgentChatWire.queueEditCapability,
      AgentChatWire.queueReorderCapability,
    },
  );
  client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
    session: agentChatSession(status: 'waiting', activeTurnId: 'turn-1'),
    turns: <Map<String, Object?>>[
      agentChatTurn('turn-1', status: 'running', completedAt: null),
    ],
    queue: <Map<String, Object?>>[
      _queued('q1', 'First queued'),
      _queued('q2', 'Second queued'),
    ],
  );
  client.handlers['agentChat.queueEdit'] = (_) => <String, Object?>{
    'updated': true,
    'queueId': 'q1',
  };
  client.handlers['agentChat.queueReorder'] = (payload) => <String, Object?>{
    'reordered': true,
    'queueId': payload['queueId'],
    'index': payload['index'],
  };
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  addTearDown(client.disconnect);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
        mobileChatTasksSupportedProvider('host')
            .overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const Scaffold(
          body: AgentChatTabView(
            hostId: 'host',
            workspaceId: 'workspace-1',
            chatId: 'chat-1',
            provider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

const ValueKey<String> _banner = ValueKey<String>(
  'agent-chat-queued-edit-banner',
);

void main() {
  testWidgets('Edit opens the message in the composer and Send saves it', (
    tester,
  ) async {
    final client = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'My draft');
    await tester.tap(find.byKey(const ValueKey<String>('queue-edit-q1')));
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsOneWidget);
    expect(_field(tester), 'First queued');
    expect(find.text('Cancel Edit'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'First, edited');
    await tester.tap(find.byTooltip('Save Queued Message'));
    await tester.pumpAndSettle();

    final edit = client.payloadsOf('agentChat.queueEdit').single;
    expect(edit['queueId'], 'q1');
    expect(edit['text'], 'First, edited');
    expect(client.payloadsOf('agentChat.send'), isEmpty);
    expect(find.byKey(_banner), findsNothing);
    expect(_field(tester), 'My draft');
  });

  testWidgets('Cancel brings the draft back without saving', (tester) async {
    final client = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'My draft');
    await tester.tap(find.byKey(const ValueKey<String>('queue-edit-q2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('composer-banner-cancel')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsNothing);
    expect(_field(tester), 'My draft');
    expect(client.payloadsOf('agentChat.queueEdit'), isEmpty);
  });

  testWidgets('a long press drags a queued message to a new place', (
    tester,
  ) async {
    final client = await _pump(tester);
    expect(find.byIcon(AleraIcons.dragHandle), findsNWidgets(2));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Second queued')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(find.text('First queued')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final move = client.payloadsOf('agentChat.queueReorder').single;
    expect(move['queueId'], 'q2');
    expect(move['index'], 0);
  });
}
