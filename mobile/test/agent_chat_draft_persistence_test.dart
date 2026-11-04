import 'dart:async';

import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/local_agent_chat_draft_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/memory_agent_chat_draft_repository.dart';

const _key = (hostId: 'host', workspaceId: 'workspace', chatId: 'chat');
AgentChatComposerDraft _draft(String text) =>
    AgentChatComposerDraft(value: TextEditingValue(text: text));

void main() {
  test(
    'repeated hydration returns the latest edit after loading an empty draft',
    () async {
      final store = AgentChatDraftStore();
      expect(
        (await store.hydrate('host', 'chat', workspaceId: 'workspace')).isEmpty,
        isTrue,
      );
      store.write(
        'host',
        'chat',
        _draft('Later edit'),
        workspaceId: 'workspace',
      );
      expect(
        (await store.hydrate('host', 'chat', workspaceId: 'workspace')).text,
        'Later edit',
      );
    },
  );
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test('device preferences restore text, selection and uploaded attachment receipts', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = LocalAgentChatDraftRepository(
      preferences: SharedPreferencesAsync(),
    );
    final first = AgentChatDraftStore(repository: repository);
    const draft = AgentChatComposerDraft(
      value: TextEditingValue(
        text: 'Unsent thought',
        selection: TextSelection(baseOffset: 2, extentOffset: 5),
      ),
      attachments: [
        AgentChatDraftAttachment(
          path: '/host/photo.png',
          source: .image,
          displayName: 'photo.png',
          attachmentId: 'opaque',
          sizeBytes: 12,
        ),
        AgentChatDraftAttachment(
          path: 'lib/main.dart',
          source: .workspaceFile,
          displayName: 'main.dart',
        ),
      ],
    );
    first.write('host', 'chat', draft, workspaceId: 'workspace');
    await first.flush();
    final restarted = AgentChatDraftStore(
      repository: LocalAgentChatDraftRepository(
        preferences: SharedPreferencesAsync(),
      ),
    );
    final restored = await restarted.hydrate(
      'host',
      'chat',
      workspaceId: 'workspace',
    );
    expect(restored.value, draft.value);
    expect(restored.attachments, draft.attachments);
    expect(restored.attachments.first.attachmentId, 'opaque');
    expect(restored.attachments.first.sizeBytes, 12);
    expect(
      (await restarted.hydrate(
        'other',
        'chat',
        workspaceId: 'workspace',
      )).isEmpty,
      isTrue,
    );
    expect(
      (await restarted.hydrate('host', 'chat', workspaceId: 'other')).isEmpty,
      isTrue,
    );
    restarted.close('host', 'chat', workspaceId: 'workspace');
    await restarted.flush();
    final closed = AgentChatDraftStore(repository: repository);
    expect(
      (await closed.hydrate('host', 'chat', workspaceId: 'workspace')).isEmpty,
      isTrue,
    );
  });

  test(
    'scoped preference keys cannot collide when identifiers contain separators',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final repository = LocalAgentChatDraftRepository(
        preferences: SharedPreferencesAsync(),
      );
      final store = AgentChatDraftStore(repository: repository);
      store.write('host.a', 'chat', _draft('A'), workspaceId: 'workspace');
      store.write('host', 'chat', _draft('B'), workspaceId: 'a.workspace');
      await store.flush();
      final restarted = AgentChatDraftStore(repository: repository);
      expect(
        (await restarted.hydrate(
          'host.a',
          'chat',
          workspaceId: 'workspace',
        )).text,
        'A',
      );
      expect(
        (await restarted.hydrate(
          'host',
          'chat',
          workspaceId: 'a.workspace',
        )).text,
        'B',
      );
    },
  );

  test(
    'late hydration keeps a typed edit while restoring pending A separately',
    () async {
      final repository = MemoryAgentChatDraftRepository();
      final first = AgentChatDraftStore(repository: repository);
      first.beginSubmission(
        'host',
        'chat',
        'id-a',
        _draft('A'),
        workspaceId: 'workspace',
      );
      first.write('host', 'chat', _draft('Old B'), workspaceId: 'workspace');
      await first.flush();
      repository.loadGate = Completer<String?>();
      final restarted = AgentChatDraftStore(repository: repository);
      final loading = restarted.hydrate(
        'host',
        'chat',
        workspaceId: 'workspace',
      );
      restarted.write(
        'host',
        'chat',
        _draft('New B'),
        workspaceId: 'workspace',
      );
      repository.loadGate!.complete(repository.snapshots[_key]);
      expect((await loading).text, 'New B');
      expect(
        restarted
            .pending('host', 'chat', workspaceId: 'workspace')
            .single
            .draft
            .text,
        'A',
      );
      await restarted.flush();
    },
  );

  test(
    'pending uploads survive optimistic clear and accepted A preserves B',
    () async {
      final repository = MemoryAgentChatDraftRepository();
      final first = AgentChatDraftStore(repository: repository);
      final a = _draft('  A  ');
      first.write('host', 'chat', a, workspaceId: 'workspace');
      first.beginSubmission(
        'host',
        'chat',
        'id-a',
        a,
        workspaceId: 'workspace',
      );
      first.write(
        'host',
        'chat',
        const AgentChatComposerDraft(),
        workspaceId: 'workspace',
      );
      await first.flushSubmission('host', 'chat', workspaceId: 'workspace');
      final restarted = AgentChatDraftStore(repository: repository);
      expect(
        (await restarted.hydrate(
          'host',
          'chat',
          workspaceId: 'workspace',
        )).isEmpty,
        isTrue,
      );
      final pending = restarted
          .pending('host', 'chat', workspaceId: 'workspace')
          .single;
      expect(pending.draft.value.text, '  A  ');
      expect(
        restarted
            .submissionIds('host', 'chat', workspaceId: 'workspace')
            .claim(a.signature, () => 'new-id'),
        'id-a',
      );
      restarted.write('host', 'chat', _draft('B'), workspaceId: 'workspace');
      restarted.settleSubmission(
        'host',
        'chat',
        'id-a',
        workspaceId: 'workspace',
      );
      await restarted.flush();
      final accepted = AgentChatDraftStore(repository: repository);
      expect(
        (await accepted.hydrate('host', 'chat', workspaceId: 'workspace')).text,
        'B',
      );
      expect(
        accepted.pending('host', 'chat', workspaceId: 'workspace'),
        isEmpty,
      );
    },
  );

  test(
    'a failed save blocks send until a later flush can retain its identity',
    () async {
      final repository = MemoryAgentChatDraftRepository()..failSave = true;
      final store = AgentChatDraftStore(repository: repository);
      store.beginSubmission(
        'host',
        'chat',
        'id-a',
        _draft('A'),
        workspaceId: 'workspace',
      );
      await expectLater(
        store.flushSubmission('host', 'chat', workspaceId: 'workspace'),
        throwsStateError,
      );
      expect(repository.saves, 1);
      repository.failSave = false;
      await store.flushSubmission('host', 'chat', workspaceId: 'workspace');
      final restarted = AgentChatDraftStore(repository: repository);
      await restarted.hydrate('host', 'chat', workspaceId: 'workspace');
      expect(
        restarted
            .pending('host', 'chat', workspaceId: 'workspace')
            .single
            .clientMessageId,
        'id-a',
      );
    },
  );

  test(
    'failed hydration cannot erase unread pending A when composer B is saved',
    () async {
      final repository = MemoryAgentChatDraftRepository();
      final first = AgentChatDraftStore(repository: repository);
      first.beginSubmission(
        'host',
        'chat',
        'id-a',
        _draft('A'),
        workspaceId: 'workspace',
      );
      await first.flush();
      repository.failLoad = true;
      final restarted = AgentChatDraftStore(repository: repository);
      await restarted.hydrate('host', 'chat', workspaceId: 'workspace');
      restarted.write('host', 'chat', _draft('B'), workspaceId: 'workspace');
      await expectLater(
        restarted.flushSubmission('host', 'chat', workspaceId: 'workspace'),
        throwsStateError,
      );
      repository.failLoad = false;
      await restarted.flushSubmission('host', 'chat', workspaceId: 'workspace');
      expect(
        restarted.read('host', 'chat', workspaceId: 'workspace').text,
        'B',
      );
      expect(
        restarted
            .pending('host', 'chat', workspaceId: 'workspace')
            .single
            .clientMessageId,
        'id-a',
      );
    },
  );

  test('hydration errors are retryable and close prevents a late read from returning a draft', () async {
    final repository = MemoryAgentChatDraftRepository();
    final first = AgentChatDraftStore(repository: repository);
    first.write('host', 'chat', _draft('Old'), workspaceId: 'workspace');
    await first.flush();
    repository.failLoad = true;
    final restarted = AgentChatDraftStore(repository: repository);
    expect(
      (await restarted.hydrate(
        'host',
        'chat',
        workspaceId: 'workspace',
      )).isEmpty,
      isTrue,
    );
    repository.failLoad = false;
    expect(
      (await restarted.hydrate('host', 'chat', workspaceId: 'workspace')).text,
      'Old',
    );
    repository.loadGate = Completer<String?>();
    final closed = AgentChatDraftStore(repository: repository);
    final loading = closed.hydrate('host', 'chat', workspaceId: 'workspace');
    closed.close('host', 'chat', workspaceId: 'workspace');
    repository.loadGate!.complete(repository.snapshots[_key]);
    expect((await loading).isEmpty, isTrue);
    expect(closed.pending('host', 'chat', workspaceId: 'workspace'), isEmpty);
    await closed.flush();
  });
}
