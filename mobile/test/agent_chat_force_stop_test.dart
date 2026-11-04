import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_force_stop.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

final _chat = agentChatControllerProvider('host', 'workspace-1', 'chat-1');

Map<String, Object?> _running({Map<String, Object?>? stop}) =>
    <String, Object?>{
      ...agentChatSession(status: 'running', activeTurnId: 'turn-1'),
      'stop': ?stop,
    };

void main() {
  test('an ignored Stop offers Force stop, which ends the turn', () async {
    final client = FakeAgentChatClient(
      capabilities: <String>{'agentChatV1', AgentChatWire.forceStopCapability},
    );
    client.handlers['agentChat.snapshot'] = (_) =>
        agentChatSnapshot(session: _running());
    client.handlers['agentChat.interrupt'] = (_) => <String, Object?>{
      'acknowledged': true,
    };
    client.handlers['agentChat.forceStop'] = (_) => <String, Object?>{
      'forceStopped': true,
    };
    final container = ProviderContainer(
      overrides: [
        agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    container.listen(_chat, (_, _) {});
    await container.read(_chat.future);
    AgentChatViewState view() => container.read(_chat).requireValue;

    await container.read(_chat.notifier).interrupt();
    expect(view().stopping, isTrue);
    expect(agentChatOffersForceStop(view(), supported: true), isFalse);

    client.emitChange(4, <String, Object?>{
      'session': _running(
        stop: <String, Object?>{
          'turnId': 'turn-1',
          'requestedAt': '2026-11-02T10:00:00Z',
          'unresponsiveAt': '2026-11-02T10:00:15Z',
        },
      ),
    });
    await pumpEventQueue();
    expect(view().stopping, isFalse);
    expect(agentChatOffersForceStop(view(), supported: true), isTrue);
    expect(agentChatOffersForceStop(view(), supported: false), isFalse);

    await forceStopAgentChat(
      await container.read(agentChatRepositoryProvider('host').future),
      view(),
    );
    expect(client.payloadsOf('agentChat.forceStop').single['turnId'], 'turn-1');
  });
}
