import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_tab_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

ProviderContainer _container(FakeAgentChatClient client) {
  final container = ProviderContainer(
    overrides: [
      agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
      mobileAgentChatClientProvider('host').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'Regenerate Title asks for a title that may replace the user one',
    () async {
      final client = FakeAgentChatClient(
        capabilities: <String>{
          'agentChatV1',
          AgentChatWire.titleGenerationCapability,
        },
      );
      client.handlers['agentChat.regenerateTitle'] = (_) => <String, Object?>{
        'titleGeneration': <String, Object?>{'status': 'generating'},
      };
      final actions = await _container(client)
          .read(agentChatTabActionsProvider('host').future);
      await actions.regenerateTitle(workspaceId: 'ws-1', chatId: 'chat-1');
      final payload = client.payloadsOf('agentChat.regenerateTitle').single;
      expect(payload['chatId'], 'chat-1');
      expect(payload['replaceUserTitle'], isTrue);
      expect(payload['requestId'], isA<String>());
    },
  );

  test('a runtime without AI chat titles refuses before sending', () async {
    final client = FakeAgentChatClient();
    final actions = await _container(client)
        .read(agentChatTabActionsProvider('host').future);
    await expectLater(
      actions.regenerateTitle(workspaceId: 'ws-1', chatId: 'chat-1'),
      throwsA(isA<AgentChatCapabilityRequired>()),
    );
    expect(client.payloadsOf('agentChat.regenerateTitle'), isEmpty);
  });
}
