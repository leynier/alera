import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
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

Map<String, Object?> _queued(
  String id,
  String text, [
  Map<String, Object?>? origin,
]) => <String, Object?>{
  'queueId': id,
  'clientMessageId': 'm-$id',
  'text': text,
  'createdAt': '2026-10-12T10:01:00Z',
  'origin': ?origin,
};

Future<void> _pump(WidgetTester tester) async {
  final repository = FakeAgentChatRepository()
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        status: 'running',
        activeTurnId: 'turn-1',
        items: <Map<String, Object?>>[
          agentChatItemFixture('u1', 'user_message', text: 'Work'),
        ],
        queue: <Map<String, Object?>>[
          _queued('q1', 'Mine'),
          _queued('q2', 'Run checks', <String, Object?>{
            'kind': 'automation',
            'automationName': 'Nightly checks',
          }),
          _queued('q3', 'CI failed', <String, Object?>{
            'kind': 'pullRequestWatch',
            'number': 42,
          }),
          _queued('q4', 'Review this', <String, Object?>{
            'kind': 'chatMessage',
            'senderChatId': 'planner-chat',
          }),
          _queued('q5', 'Hello', <String, Object?>{
            'kind': 'guest',
            'guestName': 'Ana',
          }),
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
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
        chatTaskChatProvider('planner-chat').overrideWith(
          (ref) async => AgentChatDirectoryEntry(
            chat: AgentChatSummary(
              chatId: 'planner-chat',
              workspaceId: 'ws-2',
              title: 'Planner',
              provider: 'codex',
              providerInstanceId: 'codex',
              status: AgentChatSessionStatus.ready,
              updatedAt: DateTime.utc(2026, 10, 12),
            ),
          ),
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
  await tester.pump();
}

Finder _sender(String queueId) =>
    find.byKey(ValueKey<String>('queue-sender-$queueId'));

void main() {
  testWidgets('each queued message names who sent it', (tester) async {
    await _pump(tester);
    expect(find.text('Mine'), findsOneWidget);
    expect(_sender('q1'), findsNothing);
    expect(
      find.descendant(
        of: _sender('q2'),
        matching: find.text('Automation · Nightly checks'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _sender('q3'),
        matching: find.text('Pull request #42'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an agent sender reads its chat title', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Expand Queue'));
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: _sender('q5'), matching: find.text('Guest · Ana')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _sender('q4'),
        matching: find.text('Agent · Planner'),
      ),
      findsOneWidget,
    );
  });
}
