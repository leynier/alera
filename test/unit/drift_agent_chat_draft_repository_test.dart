import 'dart:io';

import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/infra/drift_agent_chat_draft_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('draft survives closing and reopening the SQLite database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'alera-chat-drafts-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'drafts.sqlite'));
    var db = await openAleraDb(executor: NativeDatabase(file));
    final first = AgentChatComposerDrafts(
      repository: DriftAgentChatDraftRepository(() async => db),
    );
    first.write(
      'chat',
      const AgentChatComposerDraft(text: 'Unsent prompt'),
      hostId: 'host',
      workspaceId: 'workspace',
    );
    await first.flush();
    await db.close();
    db = await openAleraDb(executor: NativeDatabase(file));
    addTearDown(db.close);
    final restarted = AgentChatComposerDrafts(
      repository: DriftAgentChatDraftRepository(() async => db),
    );
    expect(
      (await restarted.hydrate(
        'chat',
        hostId: 'host',
        workspaceId: 'workspace',
      )).text,
      'Unsent prompt',
    );
    restarted.remove('chat', hostId: 'host', workspaceId: 'workspace');
    await restarted.flush();
    expect(await db.select(db.agentChatDraftsTable).get(), isEmpty);
  });

  test(
    'version 7 upgrade adds local draft storage while preserving settings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'alera-chat-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'drafts.sqlite'));
      final previous = await openAleraDb(executor: NativeDatabase(file));
      await previous.customStatement(
        'INSERT INTO app_settings_table (id, data_json) VALUES (1, ?)',
        ['{"keep":"existing"}'],
      );
      await previous.customStatement('DROP TABLE agent_chat_drafts_table');
      await previous.customStatement('PRAGMA user_version = 7');
      await previous.close();
      final upgraded = await openAleraDb(executor: NativeDatabase(file));
      addTearDown(upgraded.close);
      expect(
        (await upgraded
                .customSelect(
                  'SELECT data_json FROM app_settings_table WHERE id = 1',
                )
                .getSingle())
            .data['data_json'],
        '{"keep":"existing"}',
      );
      expect(
        await upgraded.select(upgraded.agentChatDraftsTable).get(),
        isEmpty,
      );
      final drafts = AgentChatComposerDrafts(
        repository: DriftAgentChatDraftRepository(() async => upgraded),
      );
      drafts.write(
        'chat',
        const AgentChatComposerDraft(text: 'After upgrade'),
        workspaceId: 'workspace',
      );
      await drafts.flush();
      expect(
        await upgraded.select(upgraded.agentChatDraftsTable).get(),
        hasLength(1),
      );
    },
  );
}
