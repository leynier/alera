import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_launcher.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_usage_fallback.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_usage_fallback_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

AgentChatUsageReading _reading(String provider, double used) =>
    AgentChatUsageReading(
      provider: provider,
      meters: <AgentChatUsageMeter>[
        AgentChatUsageMeter(
          usedPercent: used,
          resetsAt: DateTime.now().add(const Duration(hours: 2)),
        ),
      ],
    );

Future<(FakeAgentChatClient, ProviderContainer)> _open(
  List<AgentChatUsageReading> readings,
) async {
  final client = FakeAgentChatClient();
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[
      agentChatProviderRow('codex', label: 'Codex'),
      agentChatProviderRow('claude', provider: 'claudeAgent', label: 'Claude'),
    ],
  };
  client.handlers['agentChat.list'] = (_) => <String, Object?>{
    'chats': const <Object?>[],
  };
  client.handlers['agentChat.create'] = (payload) => <String, Object?>{
    'chatId': 'chat-new',
    'tabId': 'tab-new',
    'snapshot': agentChatSnapshot(chatId: 'chat-new'),
  };
  final container = ProviderContainer(
    overrides: [
      agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
      mobileAgentChatClientProvider('host').overrideWith((ref) async => client),
      agentChatUsageReadingsProvider('host').overrideWith((ref) => readings),
    ],
  );
  addTearDown(container.dispose);
  container
    ..listen(agentChatProvidersProvider('host', 'workspace-1'), (_, _) {})
    ..listen(agentChatPreferencesProvider('host', null), (_, _) {});
  final launcher = await agentChatLauncherFor(
    container.read,
    hostId: 'host',
    workspaceId: 'workspace-1',
  );
  await launcher.open(workspaceId: 'workspace-1', projectId: 'project');
  return (client, container);
}

void main() {
  test('New Chat skips a default agent out of usage', () async {
    final (client, container) = await _open(<AgentChatUsageReading>[
      _reading('codex', 100),
      _reading('claude', 20),
    ]);
    final payload = client.payloadsOf('agentChat.create').single;
    expect(payload['providerInstanceId'], 'claude');
    final notice = container.read(
      agentChatUsageFallbacksProvider,
    )[agentChatUsageFallbackKey('host', 'chat-new')];
    expect(notice?.title, 'Using Claude');
    expect(notice?.detail, 'Codex is out of usage');
  });

  test('New Chat keeps the default agent with usage left', () async {
    final (client, container) = await _open(<AgentChatUsageReading>[
      _reading('codex', 60),
    ]);
    final payload = client.payloadsOf('agentChat.create').single;
    expect(payload['providerInstanceId'], 'codex');
    expect(container.read(agentChatUsageFallbacksProvider), isEmpty);
  });

  testWidgets('the banner names the fallback and can be dismissed', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: AgentChatUsageFallbackBanner(
            fallback: AgentChatUsageFallback(
              selection: const AgentChatSelection(providerInstanceId: 'claude'),
              fromLabel: 'Codex',
              toLabel: 'Claude',
              resetsAt: DateTime(2026, 10, 12, 14, 30),
            ),
            now: DateTime(2026, 10, 12, 10),
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    expect(
      find.text('Using Claude · Codex is out of usage · resets at 14:30'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-usage-fallback-dismiss')),
    );
    expect(dismissed, isTrue);
  });
}
