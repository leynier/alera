import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

final _chat = agentChatControllerProvider('host', 'workspace-1', 'chat-1');

ProviderContainer _container(FakeAgentChatClient client) {
  final container = ProviderContainer(
    overrides: [
      mobileAgentChatClientProvider('host').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  container.listen(_chat, (_, _) {});
  return container;
}

AgentChatComposerDraft _draft(String text) =>
    AgentChatComposerDraft(value: TextEditingValue(text: text));

Map<String, Object?> _busySnapshot({bool steer = false}) => agentChatSnapshot(
  turns: <Map<String, Object?>>[
    agentChatTurn('turn-1', status: 'running', completedAt: null),
  ],
  items: <Map<String, Object?>>[
    agentChatItem('prompt', type: 'user_message', text: 'Build it'),
  ],
  session: agentChatSession(
    status: 'running',
    activeTurnId: 'turn-1',
    steer: steer,
  ),
);

void main() {
  test('a model picked on an idle chat is one configure', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    client.handlers['agentChat.configure'] = (_) => <String, Object?>{
      'snapshot': agentChatSnapshot(cursor: 4),
    };
    final container = _container(client);
    await container.read(_chat.future);

    await container
        .read(_chat.notifier)
        .select(
          const AgentChatSelection(providerInstanceId: 'codex', model: 'mini'),
        );

    final payload = client.payloadsOf('agentChat.configure').single;
    expect(payload['model'], 'mini');
    expect(payload.containsKey('providerInstanceId'), isFalse);
  });

  test('picking the provider default sends an explicit reset', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    client.handlers['agentChat.configure'] = (_) => <String, Object?>{
      'snapshot': agentChatSnapshot(cursor: 4),
    };
    final container = _container(client);
    await container.read(_chat.future);

    await container
        .read(_chat.notifier)
        .select(const AgentChatSelection(providerInstanceId: 'codex'));

    final payload = client.payloadsOf('agentChat.configure').single;
    expect(payload.containsKey('model'), isTrue);
    expect(payload['model'], isNull);
    expect(payload['model'], isNot(''));
  });

  test('another agent moves the same chat with one configure', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    client.handlers['agentChat.configure'] = (_) => <String, Object?>{
      'snapshot': agentChatSnapshot(cursor: 4),
    };
    final container = _container(client);
    await container.read(_chat.future);

    await container
        .read(_chat.notifier)
        .select(
          const AgentChatSelection(
            providerInstanceId: 'claudeAgent',
            model: 'opus',
          ),
        );

    final payload = client.payloadsOf('agentChat.configure').single;
    expect(payload['providerInstanceId'], 'claudeAgent');
    expect(payload['model'], 'opus');
    expect(payload['chatId'], 'chat-1');
  });

  test('a model picked while busy rides on the next message', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => _busySnapshot();
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'queued',
    };
    final container = _container(client);
    await container.read(_chat.future);
    final controller = container.read(_chat.notifier);

    await controller.select(
      const AgentChatSelection(providerInstanceId: 'codex', model: 'mini'),
    );
    expect(client.payloadsOf('agentChat.configure'), isEmpty);
    expect(container.read(_chat).requireValue.selection?.model, 'mini');

    await controller.send(_draft('Then add tests'));
    final send = client.payloadsOf('agentChat.send').single;
    expect(send['model'], 'mini');
    expect(send['delivery'], 'auto');
    expect(container.read(_chat).requireValue.pendingModel, isNull);
  });

  test('steer is sent only where the agent takes it mid-turn', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => _busySnapshot(steer: true);
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'steered',
    };
    final container = _container(client);
    await container.read(_chat.future);

    await container
        .read(_chat.notifier)
        .send(_draft('Use the other file'), steer: true);
    expect(client.payloadsOf('agentChat.send').single['delivery'], 'steer');
  });

  test('a steer request without native steer falls back to auto', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => _busySnapshot();
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'queued',
    };
    final container = _container(client);
    await container.read(_chat.future);

    await container
        .read(_chat.notifier)
        .send(_draft('Use the other file'), steer: true);
    expect(client.payloadsOf('agentChat.send').single['delivery'], 'auto');
  });

  test('a queued message steers the exact running turn in one step', () async {
    final client = FakeAgentChatClient(
      capabilities: <String>{
        AgentChatWire.capability,
        AgentChatWire.queueSteerCapability,
      },
    );
    client.handlers['agentChat.snapshot'] = (_) => _busySnapshot(steer: true);
    client.handlers['agentChat.queueSteer'] = (_) => <String, Object?>{
      'delivery': 'steered',
    };
    final container = _container(client);
    await container.read(_chat.future);

    await container
        .read(_chat.notifier)
        .steerQueued(
          AgentChatQueueEntry.fromJson(<String, Object?>{
            'queueId': 'queue-1',
            'text': 'Also fix lint',
          }),
        );

    final payload = client.payloadsOf('agentChat.queueSteer').single;
    expect(payload['queueId'], 'queue-1');
    expect(payload['turnId'], 'turn-1');
    expect(payload['requestId'], isA<String>());
  });

  test('a never-sent chat reads as ready, not stopped', () async {
    final client = FakeAgentChatClient()
      ..handlers['agentChat.snapshot'] = (_) =>
          agentChatSnapshot(session: agentChatSession(status: 'stopped'));
    final container = _container(client);
    final view = await container.read(_chat.future);
    expect(view.neverSent, isTrue);
    expect(view.thread.recovery, isNull);
    expect(view.canSwitchProvider, isTrue);
  });
}
