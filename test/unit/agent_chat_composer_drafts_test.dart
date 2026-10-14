import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_draft_repository.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Repository implements AgentChatDraftRepository {
  final Map<AgentChatDraftKey, String> snapshots = {};
  Completer<String?>? loadGate;
  Completer<void>? saveGate;
  bool failSave = false;
  bool failLoad = false;
  int saves = 0;

  @override
  Future<String?> load(AgentChatDraftKey key) async {
    if (failLoad) throw StateError('offline storage');
    return loadGate == null ? snapshots[key] : loadGate!.future;
  }

  @override
  Future<void> save(AgentChatDraftKey key, String? snapshot) async {
    saves += 1;
    await saveGate?.future;
    if (failSave) throw StateError('disk full');
    if (snapshot == null) {
      snapshots.remove(key);
    } else {
      snapshots[key] = snapshot;
    }
  }
}

const _key = (hostId: 'host', workspaceId: 'workspace', chatId: 'chat');

AgentChatComposerDraft _draft(String text) =>
    AgentChatComposerDraft(text: text);

void main() {
  test('repeated hydration returns the current edit after the first load was empty', () async {
    final store = AgentChatComposerDrafts();
    expect(
      (await store.hydrate('chat', workspaceId: 'workspace')).isEmpty,
      isTrue,
    );
    store.write('chat', _draft('Later edit'), workspaceId: 'workspace');
    expect(
      (await store.hydrate('chat', workspaceId: 'workspace')).text,
      'Later edit',
    );
  });
  test(
    'restart restores text and explicit attachment origins within one scope',
    () async {
      final repository = _Repository();
      final original = AgentChatComposerDrafts(repository: repository);
      const draft = AgentChatComposerDraft(
        text: '  Unsent thought\n',
        attachments: [
          TerminalComposerAttachment(
            id: 'image',
            kind: .image,
            path: '/local/shot.png',
            displayName: 'shot.png',
            localSourcePath: '/local/shot.png',
          ),
          TerminalComposerAttachment(
            id: 'host-file',
            kind: .file,
            path: '/host/upload.txt',
            displayName: 'upload.txt',
            attachmentId: 'opaque',
            sizeBytes: 12,
          ),
        ],
      );
      original.write('chat', draft, hostId: 'host', workspaceId: 'workspace');
      await original.flush();
      final restarted = AgentChatComposerDrafts(repository: repository);
      final restored = await restarted.hydrate(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      expect(restored.text, draft.text);
      expect(restored.attachments.first.localSourcePath, '/local/shot.png');
      expect(restored.attachments.last.attachmentId, 'opaque');
      expect(restored.attachments.last.sizeBytes, 12);
      expect(
        (await restarted.hydrate(
          'chat',
          hostId: 'other',
          workspaceId: 'workspace',
        )).isEmpty,
        isTrue,
      );
      expect(
        (await restarted.hydrate(
          'chat',
          hostId: 'host',
          workspaceId: 'other',
        )).isEmpty,
        isTrue,
      );
    },
  );

  test(
    'late hydration preserves a new edit and loads pending sends separately',
    () async {
      final repository = _Repository();
      final first = AgentChatComposerDrafts(repository: repository);
      first.beginSubmission(
        'chat',
        'id-a',
        _draft('A'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      first.write(
        'chat',
        _draft('Old B'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await first.flush();
      final snapshot = repository.snapshots[_key]!;
      repository.loadGate = Completer<String?>();
      final restarted = AgentChatComposerDrafts(repository: repository);
      final loading = restarted.hydrate(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      restarted.write(
        'chat',
        _draft('New B'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      repository.loadGate!.complete(snapshot);
      expect((await loading).text, 'New B');
      expect(
        restarted
            .pending('chat', hostId: 'host', workspaceId: 'workspace')
            .single
            .draft
            .text,
        'A',
      );
      await restarted.flush();
    },
  );

  test(
    'accepted A clears its pending receipt and preserves later composer B',
    () async {
      final repository = _Repository();
      final store = AgentChatComposerDrafts(repository: repository);
      store.beginSubmission(
        'chat',
        'id-a',
        _draft('A'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      store.write(
        'chat',
        _draft('B'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      store.settleSubmission(
        'chat',
        'id-a',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await store.flush();
      final restarted = AgentChatComposerDrafts(repository: repository);
      expect(
        (await restarted.hydrate(
          'chat',
          hostId: 'host',
          workspaceId: 'workspace',
        )).text,
        'B',
      );
      expect(
        restarted.pending('chat', hostId: 'host', workspaceId: 'workspace'),
        isEmpty,
      );
      restarted.remove('chat', hostId: 'host', workspaceId: 'workspace');
      await restarted.flush();
      expect(repository.snapshots, isEmpty);
    },
  );

  test(
    'cold unresolved A retains exact id, receipt and options separately from B',
    () async {
      final repository = _Repository();
      final first = AgentChatComposerDrafts(repository: repository);
      final a = AgentChatComposerDraft.fromMessage('A', const [
        AgentChatAttachment(
          type: .file,
          path: '/host/receipt.txt',
          name: 'input.txt',
          attachmentId: 'receipt-a',
          sizeBytes: 4,
        ),
      ]);
      first.beginSubmission(
        'chat',
        'stable-a',
        a,
        hostId: 'host',
        workspaceId: 'workspace',
        model: 'model-a',
        reasoningEffort: 'high',
        interactionMode: .plan,
        delivery: .queue,
      );
      first.write(
        'chat',
        _draft('B'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await first.flushSubmission(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      final restarted = AgentChatComposerDrafts(repository: repository);
      final b = await restarted.hydrate(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      expect(b.text, 'B');
      final pending = restarted
          .pending('chat', hostId: 'host', workspaceId: 'workspace')
          .single;
      expect(pending.clientMessageId, 'stable-a');
      expect(pending.input('chat', 'workspace').toJson(), {
        'requestId': 'stable-a',
        'clientMessageId': 'stable-a',
        'chatId': 'chat',
        'workspaceId': 'workspace',
        'text': 'A',
        'model': 'model-a',
        'reasoningEffort': 'high',
        'interactionMode': 'plan',
        'delivery': 'queue',
        'attachments': [
          {
            'type': 'file',
            'path': '/host/receipt.txt',
            'name': 'input.txt',
            'attachmentId': 'receipt-a',
            'sizeBytes': 4,
          },
        ],
      });
      expect(
        restarted.claimSubmissionId(
          'chat',
          b,
          () => 'new-b',
          hostId: 'host',
          workspaceId: 'workspace',
        ),
        'new-b',
      );
    },
  );

  test(
    'failed saves block delivery and a later flush retries the latest snapshot',
    () async {
      final repository = _Repository()..failSave = true;
      final store = AgentChatComposerDrafts(repository: repository);
      store.beginSubmission(
        'chat',
        'a',
        _draft('A'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await expectLater(
        store.flushSubmission('chat', hostId: 'host', workspaceId: 'workspace'),
        throwsStateError,
      );
      expect(repository.saves, 1);
      repository.failSave = false;
      store.write(
        'chat',
        _draft('B'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await store.flushSubmission(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      final restarted = AgentChatComposerDrafts(repository: repository);
      expect(
        (await restarted.hydrate(
          'chat',
          hostId: 'host',
          workspaceId: 'workspace',
        )).text,
        'B',
      );
      expect(
        restarted
            .pending('chat', hostId: 'host', workspaceId: 'workspace')
            .single
            .clientMessageId,
        'a',
      );
    },
  );

  test(
    'unread pending A is preserved while failed hydration keeps new B dirty',
    () async {
      final repository = _Repository();
      final first = AgentChatComposerDrafts(repository: repository);
      first.beginSubmission(
        'chat',
        'id-a',
        _draft('A'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await first.flush();
      repository.failLoad = true;
      final restarted = AgentChatComposerDrafts(repository: repository);
      await restarted.hydrate('chat', hostId: 'host', workspaceId: 'workspace');
      restarted.write(
        'chat',
        _draft('B'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await expectLater(
        restarted.flushSubmission(
          'chat',
          hostId: 'host',
          workspaceId: 'workspace',
        ),
        throwsStateError,
      );
      repository.failLoad = false;
      await restarted.flushSubmission(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      expect(
        restarted.read('chat', hostId: 'host', workspaceId: 'workspace').text,
        'B',
      );
      expect(
        restarted
            .pending('chat', hostId: 'host', workspaceId: 'workspace')
            .single
            .clientMessageId,
        'id-a',
      );
    },
  );

  test('edits during a save serialize the latest snapshot after it', () async {
    final repository = _Repository()..saveGate = Completer<void>();
    final store = AgentChatComposerDrafts(repository: repository);
    store.write(
      'chat',
      _draft('First'),
      hostId: 'host',
      workspaceId: 'workspace',
    );
    final saving = store.flush();
    await pumpEventQueue();
    store.write(
      'chat',
      _draft('Second'),
      hostId: 'host',
      workspaceId: 'workspace',
    );
    store.write(
      'chat',
      _draft('Latest'),
      hostId: 'host',
      workspaceId: 'workspace',
    );
    repository.saveGate!.complete();
    await saving;
    await store.flush();
    expect(repository.saves, 2);
    final restarted = AgentChatComposerDrafts(repository: repository);
    expect(
      (await restarted.hydrate(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      )).text,
      'Latest',
    );
  });

  test(
    'a failed hydration can be retried and an explicit remove wins a late read',
    () async {
      final repository = _Repository();
      final first = AgentChatComposerDrafts(repository: repository);
      first.write(
        'chat',
        _draft('Old'),
        hostId: 'host',
        workspaceId: 'workspace',
      );
      await first.flush();
      repository.failLoad = true;
      final restarted = AgentChatComposerDrafts(repository: repository);
      expect(
        (await restarted.hydrate(
          'chat',
          hostId: 'host',
          workspaceId: 'workspace',
        )).isEmpty,
        isTrue,
      );
      repository.failLoad = false;
      expect(
        (await restarted.hydrate(
          'chat',
          hostId: 'host',
          workspaceId: 'workspace',
        )).text,
        'Old',
      );
      repository.loadGate = Completer<String?>();
      final closed = AgentChatComposerDrafts(repository: repository);
      final loading = closed.hydrate(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      );
      closed.remove('chat', hostId: 'host', workspaceId: 'workspace');
      repository.loadGate!.complete(repository.snapshots[_key]);
      expect((await loading).isEmpty, isTrue);
      await closed.flush();
    },
  );
}
