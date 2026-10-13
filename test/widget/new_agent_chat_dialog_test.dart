import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/new_agent_chat_dialog.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

final List<AgentChatProviderInstance> _catalog = agentChatProvidersFromJson(
  <String, Object?>{
    'providers': <Object?>[
      <String, Object?>{
        'providerInstanceId': 'cursor',
        'provider': 'cursor',
        'label': 'Cursor',
        'available': false,
        'unavailableReason': 'Sign in to Cursor first.',
      },
      <String, Object?>{
        'providerInstanceId': 'pi',
        'provider': 'pi',
        'label': 'Pi',
        'runtimeModes': <Object?>['approval-required', 'full-access'],
        'interactionModes': <Object?>['default', 'plan'],
        'models': <Object?>[
          <String, Object?>{'id': 'large', 'label': 'Large', 'isDefault': true},
          <String, Object?>{'id': 'small', 'label': 'Small'},
        ],
      },
    ],
  },
);

Future<void> _pumpDialog(
  WidgetTester tester,
  FakeAgentChatRepository repository, {
  ValueChanged<AgentChatOpenResult?>? onClosed,
}) async {
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<AgentChatOpenResult>(
                context: context,
                builder: (_) => NewAgentChatDialog(workspace: _workspace),
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

AgentChatOpenResult _opened(String chatId, String tabId) => AgentChatOpenResult(
  chatId: chatId,
  tabId: tabId,
  snapshot: agentChatSnapshotFixture(),
);

void main() {
  testWidgets('an in-flight create cannot lose its result by dismissing', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..providerCatalog = _catalog
      ..createResult = _opened('chat-9', 'tab-9')
      ..createGate = Completer<void>();
    AgentChatOpenResult? closedWith;
    await _pumpDialog(
      tester,
      repository,
      onClosed: (result) => closedWith = result,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('new-agent-chat-create')),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(NewAgentChatDialog), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(NewAgentChatDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(NewAgentChatDialog), findsOneWidget);
    repository.createGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NewAgentChatDialog), findsNothing);
    expect(closedWith?.tabId, 'tab-9');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an in-flight reopen cannot lose its result by dismissing', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..providerCatalog = _catalog
      ..summaries = <AgentChatSummary>[
        AgentChatSummary.fromJson(<String, Object?>{
          'chatId': 'old-chat',
          'workspaceId': 'ws-1',
          'title': 'Earlier refactor',
          'archived': true,
          'updatedAt': '2026-10-01T10:00:00Z',
        }),
      ]
      ..reopenResult = _opened('old-chat', 'tab-3')
      ..reopenGate = Completer<void>();
    AgentChatOpenResult? closedWith;
    await _pumpDialog(
      tester,
      repository,
      onClosed: (result) => closedWith = result,
    );
    await tester.tap(find.text('Archived Chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(NewAgentChatDialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(NewAgentChatDialog), findsOneWidget);
    repository.reopenGate!.complete();
    await tester.pumpAndSettle();
    expect(closedWith?.tabId, 'tab-3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts a chat with the first available provider', (
    tester,
  ) async {
    final repository = FakeAgentChatRepository()
      ..providerCatalog = _catalog
      ..createResult = _opened('chat-9', 'tab-9');
    await _pumpDialog(tester, repository);
    expect(find.text('Pi'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('new-agent-chat-create')),
    );
    await tester.pumpAndSettle();
    final create = repository.calls.singleWhere((call) => call.$1 == 'create');
    final input = create.$2! as AgentChatCreateInput;
    expect(input.provider, 'pi');
    expect(input.providerInstanceId, 'pi');
    expect(input.model, 'large');
    expect(input.runtimeMode, AgentChatRuntimeMode.approvalRequired);
    expect(input.workspaceId, 'ws-1');
    expect(find.byType(NewAgentChatDialog), findsNothing);
  });

  testWidgets('reopens an archived chat of the workspace', (tester) async {
    final repository = FakeAgentChatRepository()
      ..providerCatalog = _catalog
      ..summaries = <AgentChatSummary>[
        AgentChatSummary.fromJson(<String, Object?>{
          'chatId': 'old-chat',
          'workspaceId': 'ws-1',
          'title': 'Earlier refactor',
          'provider': 'codex',
          'providerInstanceId': 'codex',
          'status': 'archived',
          'archived': true,
          'updatedAt': '2026-10-01T10:00:00Z',
        }),
      ]
      ..reopenResult = _opened('old-chat', 'tab-3');
    await _pumpDialog(tester, repository);
    await tester.tap(find.text('Archived Chats'));
    await tester.pumpAndSettle();
    expect(find.text('Earlier refactor'), findsOneWidget);
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    final reopen = repository.calls.singleWhere((call) => call.$1 == 'reopen');
    expect((reopen.$2! as (String, String)).$1, 'old-chat');
    expect(find.byType(NewAgentChatDialog), findsNothing);
  });

  testWidgets('a runtime refusal stays in the dialog', (tester) async {
    final repository = FakeAgentChatRepository()..providerCatalog = _catalog;
    await _pumpDialog(tester, repository);
    await tester.tap(
      find.byKey(const ValueKey<String>('new-agent-chat-create')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewAgentChatDialog), findsOneWidget);
    expect(find.text('The agent chat action failed.'), findsOneWidget);
  });
}
