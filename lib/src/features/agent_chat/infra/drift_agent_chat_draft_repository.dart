import 'dart:convert';

import 'package:alera/src/features/agent_chat/application/agent_chat_draft_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;

final class DriftAgentChatDraftRepository(
  final Future<AleraDatabase> Function() _database,
) implements AgentChatDraftRepository {
  @override
  Future<String?> load(AgentChatDraftKey key) async {
    final db = await _database();
    final row = await (db.select(
      db.agentChatDraftsTable,
    )..where((table) => table.scopeKey.equals(_scope(key)))).getSingleOrNull();
    return row?.dataJson;
  }

  @override
  Future<void> save(AgentChatDraftKey key, String? snapshot) async {
    final db = await _database();
    final scope = _scope(key);
    if (snapshot == null) {
      await (db.delete(
        db.agentChatDraftsTable,
      )..where((table) => table.scopeKey.equals(scope))).go();
      return;
    }
    await db
        .into(db.agentChatDraftsTable)
        .insertOnConflictUpdate(
          AgentChatDraftsTableCompanion(
            scopeKey: Value(scope),
            dataJson: Value(snapshot),
          ),
        );
  }

  String _scope(AgentChatDraftKey key) =>
      jsonEncode(<String>[key.hostId, key.workspaceId, key.chatId]);
}
