import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/memory_agent_chat_draft_repository.dart';

final _chat = agentChatControllerProvider('hub', 'workspace-1', 'chat-1');
AgentChatComposerDraft _draft(String text) =>
    AgentChatComposerDraft(value: TextEditingValue(text: text));

ProviderContainer _container(
  FakeAgentChatClient client,
  AgentChatDraftStore drafts,
) {
  final container = ProviderContainer(
    overrides: [
      mobileAgentChatClientProvider('hub').overrideWith((ref) async => client),
      agentChatDraftStoreProvider.overrideWithValue(drafts),
    ],
  );
  addTearDown(container.dispose);
  container.listen(_chat, (_, _) {});
  return container;
}

void main() {
  test('loading pending drafts blocks a direct Send before it can allocate a new id', () async {
    final storage = MemoryAgentChatDraftRepository();
    final first = AgentChatDraftStore(repository: storage);
    first.beginSubmission(
      'hub',
      'chat-1',
      'stable-a',
      _draft('A'),
      workspaceId: 'workspace-1',
    );
    await first.flush();
    final snapshot = storage.snapshots.values.single;
    storage.loadGate = Completer<String?>();
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    client.handlers['agentChat.send'] = (_) => {'delivery': 'started'};
    final restarted = AgentChatDraftStore(repository: storage);
    final container = _container(client, restarted);
    final loading = container.read(_chat.future);
    await pumpEventQueue();
    await expectLater(
      container.read(_chat.notifier).send(_draft('A')),
      throwsA(isA<AgentChatConnectionException>()),
    );
    expect(client.payloadsOf('agentChat.send'), isEmpty);
    storage.loadGate!.complete(snapshot);
    await loading;
    await container.read(_chat.notifier).retry('stable-a');
    expect(
      client.payloadsOf('agentChat.send').single['clientMessageId'],
      'stable-a',
    );
  });
  test('owner host unavailable reply retains exact A while a cold composer keeps B', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
      session: agentChatSession(
        status: 'running',
        activeTurnId: 'turn-a',
        steer: true,
      ),
    );
    client.handlers['agentChat.send'] = (_) => throw RuntimeRequestError(
      'owner link dropped',
      code: 'host_unavailable',
    );
    final storage = MemoryAgentChatDraftRepository();
    final firstDrafts = AgentChatDraftStore(repository: storage);
    final first = _container(client, firstDrafts);
    await first.read(_chat.future);
    final controller = first.read(_chat.notifier);
    await controller.select(
      const AgentChatSelection(providerInstanceId: 'codex', model: 'model-a'),
    );
    final a = AgentChatComposerDraft(
      value: const TextEditingValue(text: 'A'),
      attachments: const [
        AgentChatDraftAttachment(
          path: '/owner/upload.txt',
          source: .file,
          displayName: 'input.txt',
          attachmentId: 'opaque-a',
          sizeBytes: 4,
        ),
      ],
    );
    await controller.send(a, steer: true);
    final original = client.payloadsOf('agentChat.send').single;
    final id = original['clientMessageId'] as String;
    expect(
      first.read(_chat).requireValue.outbox.single.status,
      AgentChatOutgoingStatus.failed,
    );
    expect(original['model'], 'model-a');
    expect(original['delivery'], 'steer');
    firstDrafts.write('hub', 'chat-1', _draft('B'), workspaceId: 'workspace-1');
    await firstDrafts.flush();
    first.dispose();

    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    final restartedDrafts = AgentChatDraftStore(repository: storage);
    final restarted = _container(client, restartedDrafts);
    final restored = await restarted.read(_chat.future);
    expect(restored.outbox.single.clientMessageId, id);
    expect(restored.outbox.single.text, 'A');
    expect(
      restartedDrafts.read('hub', 'chat-1', workspaceId: 'workspace-1').text,
      'B',
    );
    expect(client.payloadsOf('agentChat.send'), hasLength(1));
    client.handlers['agentChat.send'] = (_) => {'delivery': 'started'};
    await restarted.read(_chat.notifier).retry(id);
    expect(client.payloadsOf('agentChat.send').last, original);
    await restarted.read(_chat.notifier).send(_draft('B'));
    final b = client.payloadsOf('agentChat.send').last;
    expect(b['clientMessageId'], isNot(id));
    expect(b['text'], 'B');
    expect(b['model'], isNull);
    expect(b['delivery'], 'auto');
    expect(
      restartedDrafts.pending('hub', 'chat-1', workspaceId: 'workspace-1'),
      isEmpty,
    );
  });

  test(
    'a draft storage failure stops the send and Retry keeps its original id',
    () async {
      final client = FakeAgentChatClient();
      client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
      client.handlers['agentChat.send'] = (_) => {'delivery': 'started'};
      final storage = MemoryAgentChatDraftRepository()..failSave = true;
      final drafts = AgentChatDraftStore(repository: storage);
      final container = _container(client, drafts);
      await container.read(_chat.future);
      await container.read(_chat.notifier).send(_draft('A'));
      expect(client.payloadsOf('agentChat.send'), isEmpty);
      final id = container
          .read(_chat)
          .requireValue
          .outbox
          .single
          .clientMessageId;
      storage.failSave = false;
      await container.read(_chat.notifier).retry(id);
      expect(client.payloadsOf('agentChat.send').single['clientMessageId'], id);
    },
  );
}
