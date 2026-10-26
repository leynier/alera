import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final Workspace _workspace = Workspace(
  id: 'ws-1',
  projectId: 'project-1',
  name: 'Alera',
  path: '/projects/alera',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

final class _Lifecycle extends AgentChatLifecycleRepository {
  _Lifecycle({required this.goal});

  final bool goal;

  @override
  Future<bool> supports(String capability) async =>
      goal && capability == AgentChatWire.goalCapability;
}

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

Future<FakeAgentChatRepository> _pump(
  WidgetTester tester, {
  Map<String, Object?>? goal,
  bool capability = true,
  bool busy = false,
}) async {
  final repository = FakeAgentChatRepository()
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        status: busy ? 'running' : 'ready',
        activeTurnId: busy ? 'turn-1' : null,
        goal: goal,
        items: <Map<String, Object?>>[
          agentChatItemFixture('u1', 'user_message', text: 'Write notes'),
        ],
      ),
    );
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(
          _Lifecycle(goal: capability),
        ),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatSurface(
            chatId: 'chat-1',
            workspace: _workspace,
            fallbackTitle: 'Agent Chat',
            fallbackProvider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return repository;
}

const _banner = ValueKey<String>('agent-chat-goal');
const _resume = ValueKey<String>('agent-chat-goal-resume');
const _clear = ValueKey<String>('agent-chat-goal-clear');

List<String> _sent(FakeAgentChatRepository repository) => <String>[
  for (final (name, input) in repository.calls)
    if (name == 'send') (input! as AgentChatSendInput).text,
];

void main() {
  testWidgets('a runtime without goals shows no banner', (tester) async {
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
        'paused',
        tokensUsed: 12500,
        tokenBudget: 50000,
        timeUsedSeconds: 125,
      ),
    );
    expect(find.byKey(_banner), findsOneWidget);
    expect(find.text('Goal paused · 13k / 50k tokens · 2m 5s'), findsOneWidget);
    expect(find.text('Ship the release notes'), findsOneWidget);
    expect(find.byKey(_resume), findsOneWidget);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('an active goal is pursued while the chat works', (tester) async {
    await _pump(tester, goal: _goal('active'), busy: true);
    expect(find.text('Pursuing goal'), findsOneWidget);
    expect(find.byKey(_resume), findsNothing);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('an idle active goal reads as set, without Resume', (
    tester,
  ) async {
    await _pump(tester, goal: _goal('active'));
    expect(find.text('Goal set'), findsOneWidget);
    expect(find.byKey(_resume), findsNothing);
  });

  testWidgets('a complete goal offers only Clear', (tester) async {
    await _pump(tester, goal: _goal('complete'));
    expect(find.text('Goal complete'), findsOneWidget);
    expect(find.byKey(_resume), findsNothing);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('Resume waits while the chat runs a turn', (tester) async {
    await _pump(tester, goal: _goal('blocked'), busy: true);
    expect(find.text('Goal blocked'), findsOneWidget);
    expect(find.byKey(_resume), findsNothing);
    expect(find.byKey(_clear), findsOneWidget);
  });

  testWidgets('Resume and Clear send the goal commands', (tester) async {
    final repository = await _pump(tester, goal: _goal('usage_limited'));
    expect(find.text('Goal hit a usage limit'), findsOneWidget);
    await tester.tap(find.byKey(_resume));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(_clear));
    await tester.pump();
    await tester.pump();
    expect(_sent(repository), <String>['/goal resume', '/goal clear']);
  });
}
