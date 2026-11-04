import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_usage_fallback.dart';
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

const Key _notice = ValueKey<String>('agent-chat-usage-fallback');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>> items = const <Map<String, Object?>>[],
  FakeAgentChatRepository? repository,
}) async {
  repository ??= FakeAgentChatRepository();
  repository.snapshots.add(() => agentChatSnapshotFixture(items: items));
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
          () => DateTime(2026, 10, 12, 10),
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
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AgentChatSurface)),
  );
  container
      .read(agentChatUsageFallbacksProvider.notifier)
      .record(
        'chat-1',
        AgentChatUsageFallback(
          selection: const AgentChatSelection(providerInstanceId: 'codex'),
          fromLabel: 'Claude',
          toLabel: 'Codex',
          resetsAt: DateTime(2026, 10, 12, 14, 30),
          defaultSelection: const AgentChatSelection(
            providerInstanceId: 'claude',
            model: 'opus',
          ),
          defaultLabel: 'Opus',
        ),
      );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('a new chat names the agent it fell back to', (tester) async {
    await _pump(tester);
    expect(find.byKey(_notice), findsOneWidget);
    expect(
      find.text('Using Codex · Claude is out of usage · resets at 14:30'),
      findsOneWidget,
    );
  });

  testWidgets('Dismiss hides the notice', (tester) async {
    final container = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-usage-fallback-dismiss')),
    );
    await tester.pump();
    expect(find.byKey(_notice), findsNothing);
    expect(container.read(agentChatUsageFallbacksProvider), isEmpty);
  });

  testWidgets('Use moves the chat back to the default agent', (tester) async {
    final repository = FakeAgentChatRepository();
    final container = await _pump(tester, repository: repository);
    await tester.tap(find.text('Use Opus'));
    await tester.pump();
    final configuration =
        repository.calls.singleWhere((call) => call.$1 == 'configure').$2!
            as AgentChatConfiguration;
    expect(configuration.providerInstanceId, 'claude');
    expect(configuration.model, 'opus');
    await tester.pump();
    expect(find.byKey(_notice), findsNothing);
    expect(container.read(agentChatUsageFallbacksProvider), isEmpty);
  });

  testWidgets('a refused switch keeps the notice', (tester) async {
    final repository = FakeAgentChatRepository()
      ..configureError = StateError('busy');
    await _pump(tester, repository: repository);
    await tester.tap(find.text('Use Opus'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_notice), findsOneWidget);
  });

  testWidgets('a chat with a sent message shows no notice', (tester) async {
    await _pump(
      tester,
      items: <Map<String, Object?>>[
        agentChatItemFixture('u1', 'user_message', text: 'Hi'),
      ],
    );
    expect(find.byKey(_notice), findsNothing);
  });
}
