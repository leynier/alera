import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_archived_chats_dialog.dart';
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

final AgentChatSummary _archived = AgentChatSummary.fromJson(<String, Object?>{
  'chatId': 'old-chat',
  'workspaceId': 'ws-1',
  'title': 'Earlier refactor',
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'status': 'archived',
  'archived': true,
  'updatedAt': '2026-10-01T10:00:00Z',
});

/// A runtime that can delete archived chats.
final class _DeletingLifecycle extends AgentChatLifecycleRepository {
  final List<(String, String)> deleted = <(String, String)>[];

  @override
  Future<bool> supports(String capability) async =>
      capability == AgentChatWire.deleteCapability;

  @override
  Future<bool> delete(AgentChatRef chat, {required String requestId}) async {
    deleted.add((chat.chatId, requestId));
    return true;
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  FakeAgentChatRepository repository, {
  AgentChatLifecycleRepository? lifecycle,
  ValueChanged<AgentChatOpenResult?>? onClosed,
}) async {
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        if (lifecycle != null)
          agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<AgentChatOpenResult>(
                context: context,
                builder: (_) =>
                    AgentChatArchivedChatsDialog(workspace: _workspace),
              );
              onClosed?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reopens an archived chat of the workspace', (tester) async {
    final repository = FakeAgentChatRepository()
      ..summaries = <AgentChatSummary>[_archived]
      ..reopenResult = AgentChatOpenResult(
        chatId: 'old-chat',
        tabId: 'tab-3',
        snapshot: agentChatSnapshotFixture(),
      );
    AgentChatOpenResult? closedWith;
    await _pumpDialog(
      tester,
      repository,
      onClosed: (result) => closedWith = result,
    );
    expect(find.text('Earlier refactor'), findsOneWidget);
    // Without the runtime capability there is nothing to delete with.
    expect(find.byTooltip('Delete Chat'), findsNothing);
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    final reopen = repository.calls.singleWhere((call) => call.$1 == 'reopen');
    expect((reopen.$2! as (String, String)).$1, 'old-chat');
    expect(closedWith?.tabId, 'tab-3');
  });

  testWidgets('an in-flight reopen cannot lose its result by dismissing', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..summaries = <AgentChatSummary>[_archived]
      ..reopenResult = AgentChatOpenResult(
        chatId: 'old-chat',
        tabId: 'tab-3',
        snapshot: agentChatSnapshotFixture(),
      )
      ..reopenGate = Completer<void>();
    AgentChatOpenResult? closedWith;
    await _pumpDialog(
      tester,
      repository,
      onClosed: (result) => closedWith = result,
    );
    await tester.tap(find.text('Reopen'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentChatArchivedChatsDialog), findsOneWidget);
    repository.reopenGate!.complete();
    await tester.pumpAndSettle();
    expect(closedWith?.tabId, 'tab-3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty archive says so', (tester) async {
    await _pumpDialog(tester, FakeAgentChatRepository());
    expect(find.text('This workspace has no archived chats.'), findsOneWidget);
  });

  testWidgets('deleting asks first and removes the chat for good', (
    tester,
  ) async {
    final lifecycle = _DeletingLifecycle();
    final repository = FakeAgentChatRepository()
      ..summaries = <AgentChatSummary>[_archived];
    await _pumpDialog(tester, repository, lifecycle: lifecycle);
    await tester.tap(find.byTooltip('Delete Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Earlier refactor?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(lifecycle.deleted, isEmpty);

    await tester.tap(find.byTooltip('Delete Chat'));
    await tester.pumpAndSettle();
    repository.summaries = const <AgentChatSummary>[];
    await tester.tap(find.widgetWithText(FilledButton, 'Delete Chat'));
    await tester.pumpAndSettle();
    expect(lifecycle.deleted.single.$1, 'old-chat');
    expect(find.text('This workspace has no archived chats.'), findsOneWidget);
  });
}
