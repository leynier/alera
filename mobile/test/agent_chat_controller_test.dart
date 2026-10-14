import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

final _chat = agentChatControllerProvider('host', 'workspace-1', 'chat-1');

ProviderContainer _container(FakeAgentChatClient client) {
  final container = ProviderContainer(
    overrides: [
      agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
      mobileAgentChatClientProvider('host').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  container.listen(_chat, (_, _) {});
  return container;
}

AgentChatViewState _view(ProviderContainer container) =>
    container.read(_chat).requireValue;

AgentChatComposerDraft _draft(String text) =>
    AgentChatComposerDraft(value: TextEditingValue(text: text));

void main() {
  test(
    'changes that arrive while the snapshot loads are applied to it',
    () async {
      final client = FakeAgentChatClient();
      final snapshot = Completer<Map<String, Object?>>();
      client.handlers['agentChat.snapshot'] = (_) => snapshot.future;
      final container = _container(client);
      final loaded = container.read(_chat.future);
      await pumpEventQueue();
      client.emitChange(4, <String, Object?>{
        'items': <Object?>[agentChatItem('answer', text: 'Done.')],
      });
      await pumpEventQueue();
      snapshot.complete(agentChatSnapshot(cursor: 3));
      final view = await loaded;
      expect(view.thread.cursor, 4);
      expect(view.thread.itemById('answer')?.text, 'Done.');
    },
  );

  test('a skipped cursor reloads the snapshot instead of guessing', () async {
    final client = FakeAgentChatClient();
    var snapshots = 0;
    client.handlers['agentChat.snapshot'] = (_) {
      snapshots += 1;
      return snapshots == 1
          ? agentChatSnapshot(cursor: 3)
          : agentChatSnapshot(
              cursor: 6,
              items: <Map<String, Object?>>[
                agentChatItem('late', text: 'Caught up.'),
              ],
            );
    };
    final container = _container(client);
    await container.read(_chat.future);
    client.emitChange(6, const <String, Object?>{});
    await pumpEventQueue();
    expect(snapshots, 2);
    expect(_view(container).thread.cursor, 6);
    expect(_view(container).thread.itemById('late')?.text, 'Caught up.');
  });

  test('a sent prompt shows until the runtime echoes it', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'started',
      'turnId': 'turn-2',
    };
    final container = _container(client);
    await container.read(_chat.future);
    await container.read(_chat.notifier).send(_draft('  Run the tests  '));
    final payload = client.payloadsOf('agentChat.send').single;
    expect(payload['text'], 'Run the tests');
    expect(payload['workspaceId'], 'workspace-1');
    expect(payload['requestId'], payload['clientMessageId']);
    expect(
      _view(container).outbox.single.status,
      AgentChatOutgoingStatus.accepted,
    );

    client.emitChange(4, <String, Object?>{
      'items': <Object?>[
        agentChatItem(
          'prompt',
          type: 'user_message',
          turnId: 'turn-2',
          text: 'Run the tests',
          clientMessageId: payload['clientMessageId']! as String,
        ),
      ],
    });
    await pumpEventQueue();
    expect(_view(container).outbox, isEmpty);
  });

  test('a refused prompt stays with the reason, and a dropped one retries under the same id', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    client.handlers['agentChat.send'] = (_) =>
        throw RuntimeRequestError('busy', code: 'turnActive');
    final container = _container(client);
    await container.read(_chat.future);
    final controller = container.read(_chat.notifier);

    await controller.send(_draft('First'));
    final refused = _view(container).outbox.single;
    expect(refused.status, AgentChatOutgoingStatus.failed);
    expect(refused.error, contains('Wait for the current turn'));

    client.handlers['agentChat.send'] = (_) =>
        throw StateError('socket closed');
    await controller.send(_draft('Second'));
    final dropped = _view(container).outbox.last;
    expect(dropped.status, AgentChatOutgoingStatus.failed);
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'queued',
    };
    await controller.retry(dropped.clientMessageId);
    final ids = <Object?>[
      for (final payload in client.payloadsOf('agentChat.send'))
        if (payload['text'] == 'Second') payload['clientMessageId'],
    ];
    expect(ids, hasLength(2));
    expect(ids.toSet(), hasLength(1));
  });

  test('Edit takes a refused prompt back into the draft', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    client.handlers['agentChat.send'] = (_) =>
        throw RuntimeRequestError('nope', code: 'unsupported');
    final container = _container(client);
    await container.read(_chat.future);
    final controller = container.read(_chat.notifier);
    await controller.send(_draft('Rewrite me'));
    controller.edit(_view(container).outbox.single.clientMessageId);
    expect(_view(container).outbox, isEmpty);
    expect(
      container
          .read(agentChatDraftStoreProvider)
          .read('host', 'chat-1', workspaceId: 'workspace-1')
          .text,
      'Rewrite me',
    );
  });

  test(
    'an answer another device already gave reloads instead of failing',
    () async {
      final client = FakeAgentChatClient();
      final request = <String, Object?>{
        'requestId': 'request-1',
        'kind': 'command_execution_approval',
        'createdAt': '2026-10-12T10:00:00Z',
        'decisions': <String>['accept', 'decline'],
      };
      var snapshots = 0;
      client.handlers['agentChat.snapshot'] = (_) {
        snapshots += 1;
        return agentChatSnapshot(
          cursor: 2 + snapshots,
          pendingRequests: snapshots == 1
              ? <Map<String, Object?>>[request]
              : const <Map<String, Object?>>[],
        );
      };
      client.handlers['agentChat.respond'] = (_) =>
          throw RuntimeRequestError('answered', code: 'request_resolved');
      final container = _container(client);
      await container.read(_chat.future);
      final pending = _view(container).thread.pendingRequests.single;
      await container
          .read(_chat.notifier)
          .respond(
            pending,
            const AgentChatApprovalResponse(AgentChatApprovalDecision.accept),
          );
      await pumpEventQueue();
      final payload = client.payloadsOf('agentChat.respond').single;
      expect(payload['runtimeRequestId'], 'request-1');
      expect(payload['response'], <String, Object?>{
        'type': 'approval',
        'decision': 'accept',
      });
      expect(snapshots, 2);
      expect(_view(container).thread.pendingRequests, isEmpty);
      expect(_view(container).respondingRequestIds, isEmpty);
    },
  );

  test('Stop stays pressed until the turn actually ends', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
      session: agentChatSession(status: 'running', activeTurnId: 'turn-1'),
    );
    client.handlers['agentChat.interrupt'] = (_) => <String, Object?>{
      'acknowledged': true,
    };
    final container = _container(client);
    await container.read(_chat.future);
    await container.read(_chat.notifier).interrupt();
    expect(client.payloadsOf('agentChat.interrupt').single['turnId'], 'turn-1');
    expect(_view(container).interrupting, isTrue);

    client.emitChange(4, <String, Object?>{'session': agentChatSession()});
    await pumpEventQueue();
    expect(_view(container).interrupting, isFalse);
  });

  test('a dropped connection keeps the last copy and marks it stale', () async {
    final client = FakeAgentChatClient();
    client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
      items: <Map<String, Object?>>[agentChatItem('answer', text: 'Kept.')],
    );
    final container = _container(client);
    await container.read(_chat.future);
    await client.disconnect();
    await pumpEventQueue();
    final view = _view(container);
    expect(view.stale, isTrue);
    expect(view.thread.itemById('answer')?.text, 'Kept.');
  });

  test('a reconnect turns a prompt that was on its way into a Retry', () async {
    final client = FakeAgentChatClient();
    var snapshots = 0;
    client.handlers['agentChat.snapshot'] = (_) {
      snapshots += 1;
      return agentChatSnapshot(cursor: 2 + snapshots);
    };
    client.handlers['agentChat.send'] = (_) =>
        Completer<Map<String, Object?>>().future;
    final container = _container(client);
    await container.read(_chat.future);
    unawaited(container.read(_chat.notifier).send(_draft('Mid flight')));
    await pumpEventQueue();
    expect(
      _view(container).outbox.single.status,
      AgentChatOutgoingStatus.sending,
    );

    container.invalidate(mobileAgentChatClientProvider('host'));
    await pumpEventQueue();
    expect(snapshots, 2);
    final message = _view(container).outbox.single;
    expect(message.status, AgentChatOutgoingStatus.failed);
    expect(message.text, 'Mid flight');
  });

  test('an older runtime fails closed with Update Required', () async {
    final client = FakeAgentChatClient(capabilities: <String>{});
    final container = _container(client);
    // Riverpod keeps retrying in the background, so read the state rather
    // than awaiting a future that waits for the retries to run out.
    await pumpEventQueue();
    expect(container.read(_chat).error, isA<AgentChatUpdateRequired>());
    expect(client.calls, isEmpty);
  });
}
