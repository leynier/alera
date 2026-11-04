import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_attachment_preparation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_draft_repository.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final class _DraftRepository implements AgentChatDraftRepository {
  final Map<AgentChatDraftKey, String> snapshots = {};
  bool failSave = false;
  bool failLoad = false;
  Completer<String?>? loadGate;
  @override
  Future<String?> load(AgentChatDraftKey key) async {
    if (failLoad) throw StateError('read failed');
    return loadGate == null ? snapshots[key] : loadGate!.future;
  }

  @override
  Future<void> save(AgentChatDraftKey key, String? snapshot) async {
    if (failSave) throw StateError('disk full');
    if (snapshot == null) {
      snapshots.remove(key);
    } else {
      snapshots[key] = snapshot;
    }
  }
}

final _chat = agentChatControllerProvider('chat-1', 'ws-1');

const _localFile = AgentChatAttachment(
  type: .file,
  path: '/client/input.txt',
  name: 'input.txt',
  localSourcePath: '/client/input.txt',
);
const _uploadedFile = AgentChatAttachment(
  type: .file,
  path: '/owner/input.txt',
  name: 'input.txt',
  attachmentId: 'receipt-a',
  sizeBytes: 4,
);

ProviderContainer _container(
  FakeAgentChatRepository repository,
  AgentChatComposerDrafts drafts,
  String id,
  AgentChatPrepareAttachments prepare, {
  String Function()? nextId,
}) {
  final container = ProviderContainer(
    overrides: [
      agentChatRepositoryProvider.overrideWithValue(repository),
      agentChatComposerDraftsProvider.overrideWithValue(drafts),
      agentChatIdGeneratorProvider.overrideWithValue(nextId ?? () => id),
      agentChatPrepareAttachmentsProvider.overrideWithValue(prepare),
    ],
  );
  addTearDown(container.dispose);
  container.listen(_chat, (_, _) {});
  return container;
}

List<AgentChatSendInput> _sends(FakeAgentChatRepository repository) => [
  for (final call in repository.calls)
    if (call.$1 == 'send') call.$2 as AgentChatSendInput,
];

void main() {
  test(
    'an uploading A preserves both drafts and reaches the runtime before B',
    () async {
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture());
      final storage = _DraftRepository();
      final drafts = AgentChatComposerDrafts(repository: storage);
      final prepare = Completer<List<AgentChatAttachment>>();
      var next = 0;
      final container = _container(
        repository,
        drafts,
        'unused',
        (_, _, _) => prepare.future,
        nextId: () => 'fifo-${next++}',
      );
      await pumpEventQueue();
      expect(container.read(_chat).preparingAttachments, isFalse);
      final controller = container.read(_chat.notifier);
      expect(
        controller.send('A', attachments: const [_localFile], delivery: .queue),
        isTrue,
      );
      await pumpEventQueue();
      expect(container.read(_chat).preparingAttachments, isTrue);
      expect(controller.send('B'), isTrue);
      await pumpEventQueue();
      expect(_sends(repository), isEmpty);
      final cold = AgentChatComposerDrafts(repository: storage);
      await cold.hydrate('chat-1', workspaceId: 'ws-1');
      final retained = cold.pending('chat-1', workspaceId: 'ws-1');
      expect(retained.map((submission) => submission.draft.text), ['A', 'B']);
      expect(retained.map((submission) => submission.clientMessageId), [
        'fifo-0',
        'fifo-1',
      ]);
      expect(retained.first.delivery, AgentChatDelivery.queue);
      expect(
        retained.first
            .input('chat-1', 'ws-1')
            .attachments
            .single
            .localSourcePath,
        '/client/input.txt',
      );
      prepare.complete(const [_uploadedFile]);
      await pumpEventQueue();
      expect(_sends(repository).map((input) => input.text), ['A', 'B']);
      expect(_sends(repository).map((input) => input.clientMessageId), [
        'fifo-0',
        'fifo-1',
      ]);
      expect(
        _sends(repository).first.attachments.single.attachmentId,
        'receipt-a',
      );
      expect(container.read(_chat).preparingAttachments, isFalse);
      expect(drafts.pending('chat-1', workspaceId: 'ws-1'), isEmpty);
    },
  );

  test(
    'failed preparation of A releases B without losing the failed submission',
    () async {
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture());
      final storage = _DraftRepository();
      final drafts = AgentChatComposerDrafts(repository: storage);
      final prepare = Completer<List<AgentChatAttachment>>();
      var next = 0;
      final container = _container(
        repository,
        drafts,
        'unused',
        (_, _, _) => prepare.future,
        nextId: () => 'failed-${next++}',
      );
      await pumpEventQueue();
      final controller = container.read(_chat.notifier);
      controller.send('A', attachments: const [_localFile]);
      await pumpEventQueue();
      controller.send('B');
      await pumpEventQueue();
      expect(_sends(repository), isEmpty);
      prepare.completeError(StateError('Upload failed'));
      await pumpEventQueue();
      expect(_sends(repository).map((input) => input.text), ['B']);
      expect(
        container.read(_chat).outgoing.first.status,
        AgentChatOutgoingStatus.failed,
      );
      expect(
        container.read(_chat).outgoing.last.status,
        AgentChatOutgoingStatus.accepted,
      );
      expect(
        drafts.pending('chat-1', workspaceId: 'ws-1').single.draft.text,
        'A',
      );
      expect(container.read(_chat).preparingAttachments, isFalse);
    },
  );

  test(
    'disposing the owner prevents A and queued B from making native sends',
    () async {
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture());
      final storage = _DraftRepository();
      final drafts = AgentChatComposerDrafts(repository: storage);
      final prepare = Completer<List<AgentChatAttachment>>();
      var next = 0;
      final container = _container(
        repository,
        drafts,
        'unused',
        (_, _, _) => prepare.future,
        nextId: () => 'closed-${next++}',
      );
      await pumpEventQueue();
      final controller = container.read(_chat.notifier);
      controller.send('A', attachments: const [_localFile]);
      await pumpEventQueue();
      controller.send('B');
      await pumpEventQueue();
      container.dispose();
      prepare.complete(const [_uploadedFile]);
      await pumpEventQueue();
      expect(_sends(repository), isEmpty);
      final cold = AgentChatComposerDrafts(repository: storage);
      await cold.hydrate('chat-1', workspaceId: 'ws-1');
      final retained = cold.pending('chat-1', workspaceId: 'ws-1');
      expect(retained.map((submission) => submission.draft.text), ['A', 'B']);
      expect(
        retained.first.input('chat-1', 'ws-1').attachments.single.attachmentId,
        'receipt-a',
      );
    },
  );
  test(
    'Send cannot allocate a new id before pending drafts finish loading',
    () async {
      final storage = _DraftRepository();
      final first = AgentChatComposerDrafts(repository: storage);
      first.beginSubmission(
        'chat-1',
        'stable-a',
        const AgentChatComposerDraft(text: 'A'),
        workspaceId: 'ws-1',
      );
      await first.flush();
      final snapshot = storage.snapshots.values.single;
      storage.loadGate = Completer<String?>();
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture());
      final restarted = AgentChatComposerDrafts(repository: storage);
      final container = _container(
        repository,
        restarted,
        'fresh-id',
        (_, attachments, _) async => attachments,
      );
      await pumpEventQueue();
      expect(container.read(_chat).canSend, isFalse);
      expect(container.read(_chat.notifier).send('A'), isFalse);
      expect(_sends(repository), isEmpty);
      storage.loadGate!.complete(snapshot);
      await pumpEventQueue();
      expect(container.read(_chat).canSend, isTrue);
      expect(container.read(_chat.notifier).send('A'), isTrue);
      await pumpEventQueue();
      expect(_sends(repository).single.clientMessageId, 'stable-a');
    },
  );

  test(
    'an unread draft keeps sending blocked until the chat is retried',
    () async {
      final storage = _DraftRepository()..failLoad = true;
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture());
      final drafts = AgentChatComposerDrafts(repository: storage);
      final container = _container(
        repository,
        drafts,
        'fresh-id',
        (_, attachments, _) async => attachments,
      );
      await pumpEventQueue();
      expect(container.read(_chat).canSend, isFalse);
      expect(container.read(_chat.notifier).send('A'), isFalse);
      expect(_sends(repository), isEmpty);
      storage.failLoad = false;
      await container.read(_chat.notifier).retry();
      expect(container.read(_chat).canSend, isTrue);
    },
  );
  test(
    'lost reply followed by restart keeps A receipt/id separate from typed B',
    () async {
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture())
        ..sendError = const AgentChatConnectionException('reply lost');
      final storage = _DraftRepository();
      final firstDrafts = AgentChatComposerDrafts(repository: storage);
      var uploads = 0;
      final first = _container(repository, firstDrafts, 'stable-a', (
        chat,
        attachments,
        id,
      ) async {
        uploads += 1;
        return const [
          AgentChatAttachment(
            type: .file,
            path: '/owner/upload.txt',
            name: 'input.txt',
            attachmentId: 'opaque-a',
            sizeBytes: 4,
          ),
        ];
      });
      await pumpEventQueue();
      final controller = first.read(_chat.notifier);
      expect(
        controller.send(
          'A',
          attachments: const [
            AgentChatAttachment(
              type: .file,
              path: '/client/input.txt',
              name: 'input.txt',
              localSourcePath: '/client/input.txt',
            ),
          ],
        ),
        isTrue,
      );
      firstDrafts.write(
        'chat-1',
        AgentChatComposerDraft.empty,
        workspaceId: 'ws-1',
      );
      await pumpEventQueue();
      expect(
        first.read(_chat).outgoing.single.status,
        AgentChatOutgoingStatus.failed,
      );
      final original = _sends(repository).single.toJson();
      expect(original.toString(), isNot(contains('localSourcePath')));
      firstDrafts.write(
        'chat-1',
        const AgentChatComposerDraft(text: 'B'),
        workspaceId: 'ws-1',
      );
      await firstDrafts.flush();
      first.dispose();

      final restartedDrafts = AgentChatComposerDrafts(repository: storage);
      final restarted = _container(
        repository,
        restartedDrafts,
        'new-b',
        (_, _, _) async => throw StateError('receipt must not upload again'),
      );
      await pumpEventQueue();
      expect(restartedDrafts.read('chat-1', workspaceId: 'ws-1').text, 'B');
      expect(restarted.read(_chat).outgoing.single.clientMessageId, 'stable-a');
      expect(restarted.read(_chat).outgoing.single.text, 'A');
      expect(_sends(repository), hasLength(1));
      repository.sendError = null;
      await restarted.read(_chat.notifier).retrySend('stable-a');
      expect(_sends(repository).last.toJson(), original);
      expect(uploads, 1);
      expect(restarted.read(_chat.notifier).send('B'), isTrue);
      restartedDrafts.write(
        'chat-1',
        AgentChatComposerDraft.empty,
        workspaceId: 'ws-1',
      );
      await pumpEventQueue();
      expect(_sends(repository).last.clientMessageId, 'new-b');
      expect(_sends(repository).last.text, 'B');
      expect(restartedDrafts.pending('chat-1', workspaceId: 'ws-1'), isEmpty);
    },
  );

  test(
    'failed durable capture prevents native send until explicit Retry',
    () async {
      final repository = FakeAgentChatRepository()
        ..snapshots.add(() => agentChatSnapshotFixture());
      final storage = _DraftRepository()..failSave = true;
      final drafts = AgentChatComposerDrafts(repository: storage);
      final container = _container(
        repository,
        drafts,
        'stable-id',
        (_, attachments, _) async => attachments,
      );
      await pumpEventQueue();
      expect(container.read(_chat.notifier).send('A'), isTrue);
      await pumpEventQueue();
      expect(_sends(repository), isEmpty);
      expect(
        container.read(_chat).outgoing.single.status,
        AgentChatOutgoingStatus.failed,
      );
      storage.failSave = false;
      await container.read(_chat.notifier).retrySend('stable-id');
      expect(_sends(repository).single.clientMessageId, 'stable-id');
    },
  );
}
