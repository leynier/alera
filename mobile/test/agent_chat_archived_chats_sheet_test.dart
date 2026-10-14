import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_archived_chats_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

Future<String? Function()> _openSheet(
  WidgetTester tester,
  FakeAgentChatClient client,
) async {
  String? opened;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  opened = await showAgentChatArchivedChatsSheet(
                    context,
                    hostId: 'host',
                    workspaceId: 'workspace-1',
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return () => opened;
}

FakeAgentChatClient _client({Set<String>? capabilities}) {
  final client = FakeAgentChatClient(capabilities: capabilities);
  client.handlers['agentChat.list'] = (_) => <String, Object?>{
    'chats': <Object?>[
      <String, Object?>{
        'chatId': 'chat-old',
        'workspaceId': 'workspace-1',
        'title': 'Earlier refactor',
        'provider': 'claudeAgent',
        'providerInstanceId': 'claudeAgent',
        'status': 'stopped',
        'updatedAt': '2026-10-11T08:00:00Z',
        'archived': true,
      },
      <String, Object?>{
        'chatId': 'chat-open',
        'workspaceId': 'workspace-1',
        'title': 'Still open',
        'provider': 'codex',
        'providerInstanceId': 'codex',
        'status': 'ready',
        'updatedAt': '2026-10-12T08:00:00Z',
      },
    ],
  };
  return client;
}

void main() {
  testWidgets('Reopen continues an archived chat in a new tab', (tester) async {
    final client = _client()
      ..handlers['agentChat.reopen'] = (_) => <String, Object?>{
        'chatId': 'chat-old',
        'tabId': 'tab-reopened',
        'snapshot': agentChatSnapshot(),
      };
    final opened = await _openSheet(tester, client);
    expect(find.text('Earlier refactor'), findsOneWidget);
    expect(find.text('Still open'), findsNothing);
    expect(find.byTooltip('Delete Chat'), findsNothing);

    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.reopen').single['chatId'], 'chat-old');
    expect(opened(), 'tab-reopened');
  });

  testWidgets('a retried Reopen keeps its request id', (tester) async {
    var attempts = 0;
    final client = _client()
      ..handlers['agentChat.reopen'] = (_) {
        attempts += 1;
        if (attempts == 1) throw StateError('closed');
        return <String, Object?>{
          'chatId': 'chat-old',
          'tabId': 'tab-reopened',
          'snapshot': agentChatSnapshot(),
        };
      };
    await _openSheet(tester, client);
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    final ids = <Object?>[
      for (final payload in client.payloadsOf('agentChat.reopen'))
        payload['requestId'],
    ];
    expect(ids, hasLength(2));
    expect(ids.first, ids.last);
  });

  testWidgets('Delete asks first and removes the chat from the host', (
    tester,
  ) async {
    final client = _client(
      capabilities: <String>{
        AgentChatWire.capability,
        AgentChatWire.deleteCapability,
      },
    )..handlers['agentChat.delete'] = (_) => <String, Object?>{'deleted': true};
    await _openSheet(tester, client);
    await tester.tap(find.byTooltip('Delete Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Chat?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.delete').single['chatId'], 'chat-old');
  });
}
