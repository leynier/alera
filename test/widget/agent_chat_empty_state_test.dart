import 'package:alera/src/app/theme/alera_dark_theme.dart';
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

const String _invite = 'Send a message to start.';
final Finder _hint = find.byKey(
  const ValueKey<String>('agent-chat-empty-hint'),
);

Future<FakeAgentChatRepository> _pump(
  WidgetTester tester,
  AgentChatSnapshot snapshot,
) async {
  final repository = FakeAgentChatRepository()..snapshots.add(() => snapshot);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 13),
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
  expect(find.byKey(const ValueKey<String>('agent-chat-empty')), findsOne);
  return repository;
}

String? _hintText(WidgetTester tester) =>
    _hint.evaluate().isEmpty ? null : tester.widget<Text>(_hint).data;

void main() {
  testWidgets('a ready chat invites the first message', (tester) async {
    await _pump(tester, agentChatSnapshotFixture());
    expect(_hintText(tester), _invite);
  });

  testWidgets('a stopped chat with recovery points at the recovery actions', (
    tester,
  ) async {
    await _pump(
      tester,
      agentChatSnapshotFixture(
        status: 'stopped',
        recovery: <String, Object?>{
          'kind': 'resumable',
          'message': 'The Alera runtime restarted and stopped this chat.',
          'canResume': true,
          'canRestart': true,
        },
      ),
    );
    expect(
      _hintText(tester),
      'The agent session stopped. Resume it or start a new session below.',
    );
    expect(find.text(_invite), findsNothing);
    expect(find.text('Resume Session'), findsOneWidget);
  });

  testWidgets('a stopped chat without a way back does not invite a send', (
    tester,
  ) async {
    await _pump(
      tester,
      agentChatSnapshotFixture(
        status: 'error',
        recovery: <String, Object?>{
          'kind': 'providerMissing',
          'message': 'The provider is not installed.',
        },
      ),
    );
    expect(_hintText(tester), 'The agent session stopped.');
  });

  testWidgets('an archived chat says so instead of inviting a send', (
    tester,
  ) async {
    await _pump(tester, agentChatSnapshotFixture().copyWith(archived: true));
    expect(_hintText(tester), 'This chat is archived.');
  });

  testWidgets('a lost runtime connection replaces the invitation', (
    tester,
  ) async {
    final repository = await _pump(tester, agentChatSnapshotFixture());
    repository.events.add(const AgentChatConnectionLost());
    // The event lands after the first frame; the second one shows it.
    await tester.pump();
    await tester.pump();
    expect(_hintText(tester), 'Waiting for the Alera runtime to reconnect.');
    expect(find.text(_invite), findsNothing);
  });
}
