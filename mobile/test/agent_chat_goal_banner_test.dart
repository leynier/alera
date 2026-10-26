import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_goal_continuation_marker.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

Map<String, Object?> _goal(
  String status, {
  int? tokensUsed,
  int? tokenBudget,
  int? timeUsedSeconds,
}) => <String, Object?>{
  'objective': 'Ship the release notes',
  'status': status,
  'tokensUsed': ?tokensUsed,
  'tokenBudget': ?tokenBudget,
  'timeUsedSeconds': ?timeUsedSeconds,
};

Future<FakeAgentChatClient> _pump(
  WidgetTester tester, {
  Map<String, Object?>? goal,
  bool capability = true,
  bool busy = false,
  String? origin,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = FakeAgentChatClient(
    capabilities: <String>{
      AgentChatWire.capability,
      if (capability) AgentChatWire.goalCapability,
    },
  );
  client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
    session: <String, Object?>{
      ...agentChatSession(
        status: busy ? 'running' : 'ready',
        activeTurnId: busy ? 'turn-1' : null,
      ),
      'goal': ?goal,
    },
    turns: <Map<String, Object?>>[
      <String, Object?>{
        ...agentChatTurn(
          'turn-1',
          status: busy ? 'running' : 'completed',
          completedAt: busy ? null : '2026-10-12T10:00:04Z',
        ),
        'origin': ?origin,
      },
    ],
    items: <Map<String, Object?>>[
      agentChatItem('a1', text: 'Drafted the notes.'),
    ],
  );
  client.handlers['agentChat.send'] = (_) => <String, Object?>{
    'delivery': 'started',
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

const _banner = ValueKey<String>('agent-chat-goal');
const _resume = ValueKey<String>('agent-chat-goal-resume');
const _clear = ValueKey<String>('agent-chat-goal-clear');

void main() {
  testWidgets('a host without goals shows no banner', (tester) async {
    await _pump(tester, goal: _goal('paused'), capability: false);
    expect(find.byKey(_banner), findsNothing);
  });

  testWidgets('a chat without a goal shows no banner', (tester) async {
    await _pump(tester);
    expect(find.byKey(_banner), findsNothing);
  });

  testWidgets('shows the title, the usage and the objective', (tester) async {
    await _pump(
      tester,
      goal: _goal(
        'budget_limited',
        tokensUsed: 50000,
        tokenBudget: 50000,
        timeUsedSeconds: 600,
      ),
    );
    expect(
      find.text('Goal reached its token budget · 50k / 50k tokens · 10m'),
      findsOneWidget,
    );
    expect(find.text('Ship the release notes'), findsOneWidget);
    expect(find.byKey(_resume), findsOneWidget);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('Resume waits while the chat runs a turn', (tester) async {
    await _pump(tester, goal: _goal('paused'), busy: true);
    expect(find.text('Goal paused'), findsOneWidget);
    expect(find.byKey(_resume), findsNothing);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('an active goal offers only Clear', (tester) async {
    await _pump(tester, goal: _goal('active'), busy: true);
    expect(find.text('Pursuing goal'), findsOneWidget);
    expect(find.byKey(_resume), findsNothing);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('a complete goal offers only Clear', (tester) async {
    await _pump(tester, goal: _goal('complete'));
    expect(find.text('Goal complete'), findsOneWidget);
    expect(find.byKey(_resume), findsNothing);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('Resume and Clear send the goal commands', (tester) async {
    final client = await _pump(tester, goal: _goal('blocked'));
    await tester.tap(find.byKey(_resume));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_clear));
    await tester.pumpAndSettle();
    expect(
      <Object?>[
        for (final payload in client.payloadsOf('agentChat.send'))
          payload['text'],
      ],
      <String>['/goal resume', '/goal clear'],
    );
  });

  testWidgets('a goal continuation turn shows a marker for its prompt', (
    tester,
  ) async {
    await _pump(tester, origin: 'goalContinuation');
    expect(find.text(AgentChatGoalContinuationMarker.label), findsOneWidget);
    expect(find.text('Drafted the notes.'), findsOneWidget);
  });

  testWidgets('a turn without an origin shows no marker', (tester) async {
    await _pump(tester);
    expect(find.text(AgentChatGoalContinuationMarker.label), findsNothing);
    expect(find.text('Drafted the notes.'), findsOneWidget);
  });
}
