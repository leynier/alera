import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/new_agent_chat_sheet.dart';
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
              onPressed: () async => opened = await showNewAgentChatSheet(
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

FakeAgentChatClient _client() {
  final client = FakeAgentChatClient();
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[
      <String, Object?>{
        'providerInstanceId': 'codex',
        'provider': 'codex',
        'label': 'Codex',
        'models': <Object?>[
          <String, Object?>{'id': 'gpt-5', 'label': 'GPT-5', 'isDefault': true},
          <String, Object?>{'id': 'gpt-5-mini', 'label': 'GPT-5 Mini'},
        ],
      },
      <String, Object?>{
        'providerInstanceId': 'cursor',
        'provider': 'cursor',
        'label': 'Cursor',
        'available': false,
        'unavailableReason': 'Sign in to Cursor on the host.',
      },
    ],
  };
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
    ],
  };
  return client;
}

void main() {
  testWidgets('Start Chat creates the chosen agent and model', (tester) async {
    final client = _client()
      ..handlers['agentChat.create'] = (_) => <String, Object?>{
        'chatId': 'chat-9',
        'tabId': 'tab-9',
        'snapshot': agentChatSnapshot(),
      };
    final opened = await _openSheet(tester, client);
    expect(find.text('Sign in to Cursor on the host.'), findsOneWidget);

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-5 Mini'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Chat'));
    await tester.pumpAndSettle();

    final payload = client.payloadsOf('agentChat.create').single;
    expect(payload['provider'], 'codex');
    expect(payload['providerInstanceId'], 'codex');
    expect(payload['model'], 'gpt-5-mini');
    expect(payload['workspaceId'], 'workspace-1');
    expect(payload['requestId'], isA<String>());
    expect(opened(), 'tab-9');
  });

  testWidgets('Reopen continues an archived chat in a new tab', (tester) async {
    final client = _client()
      ..handlers['agentChat.reopen'] = (_) => <String, Object?>{
        'chatId': 'chat-old',
        'tabId': 'tab-reopened',
        'snapshot': agentChatSnapshot(),
      };
    final opened = await _openSheet(tester, client);
    expect(find.text('Earlier refactor'), findsOneWidget);

    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.reopen').single['chatId'], 'chat-old');
    expect(opened(), 'tab-reopened');
  });
}
