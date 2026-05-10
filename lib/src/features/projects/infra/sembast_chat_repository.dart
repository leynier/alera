import 'package:alera/src/features/projects/application/chat_repository.dart';
import 'package:alera/src/features/projects/domain/chat_message.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:sembast/sembast.dart';

class SembastChatRepository implements ChatRepository {
  SembastChatRepository(this._db);

  final Database _db;

  @override
  Future<List<ChatSummary>> listByProject(String projectId) async {
    final records = await AleraStores.chats.find(
      _db,
      finder: Finder(
        filter: Filter.equals('projectId', projectId),
        sortOrders: <SortOrder>[SortOrder('updatedAt', false)],
      ),
    );
    return records
        .map((r) => ChatSummary.fromJson(r.value))
        .toList(growable: false);
  }

  @override
  Stream<List<ChatSummary>> watchByProject(String projectId) {
    return AleraStores.chats
        .query(
          finder: Finder(
            filter: Filter.equals('projectId', projectId),
            sortOrders: <SortOrder>[SortOrder('updatedAt', false)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => records
              .map((r) => ChatSummary.fromJson(r.value))
              .toList(growable: false),
        );
  }

  @override
  Future<ChatSummary?> findById(String chatId) async {
    final record = await AleraStores.chats.record(chatId).get(_db);
    if (record == null) {
      return null;
    }
    return ChatSummary.fromJson(record);
  }

  @override
  Future<ChatSummary> upsert(ChatSummary chat) async {
    await AleraStores.chats.record(chat.id).put(_db, chat.toJson());
    return chat;
  }

  @override
  Future<void> remove(String chatId, {bool cascadeMessages = true}) async {
    await _db.transaction((txn) async {
      await AleraStores.chats.record(chatId).delete(txn);
      if (!cascadeMessages) {
        return;
      }
      final messages = await AleraStores.chatMessages.find(
        txn,
        finder: Finder(filter: Filter.equals('chatId', chatId)),
      );
      for (final m in messages) {
        await AleraStores.chatMessages.record(m.key).delete(txn);
      }
      final cells = await AleraStores.chatCells.find(
        txn,
        finder: Finder(filter: Filter.equals('chatId', chatId)),
      );
      for (final c in cells) {
        await AleraStores.chatCells.record(c.key).delete(txn);
      }
    });
  }

  @override
  Future<List<ChatMessage>> loadMessages(String chatId) async {
    final records = await AleraStores.chatMessages.find(
      _db,
      finder: Finder(
        filter: Filter.equals('chatId', chatId),
        sortOrders: <SortOrder>[SortOrder('seq', true)],
      ),
    );
    return records
        .map((r) => ChatMessage.fromJson(r.value))
        .toList(growable: false);
  }

  @override
  Future<int> nextSeq(String chatId) async {
    final records = await AleraStores.chatMessages.find(
      _db,
      finder: Finder(
        filter: Filter.equals('chatId', chatId),
        sortOrders: <SortOrder>[SortOrder('seq', false)],
        limit: 1,
      ),
    );
    if (records.isEmpty) {
      return 0;
    }
    final latest = records.first.value['seq'];
    if (latest is! int) {
      return 0;
    }
    return latest + 1;
  }

  @override
  Future<ChatMessage> appendMessage(ChatMessage message) async {
    final id = chatMessageRecordId(chatId: message.chatId, seq: message.seq);
    await AleraStores.chatMessages.record(id).put(_db, message.toJson());
    return message;
  }

  @override
  Future<void> replaceCells(String chatId, List<TimelineCell> cells) async {
    await _db.transaction((txn) async {
      final existing = await AleraStores.chatCells.find(
        txn,
        finder: Finder(filter: Filter.equals('chatId', chatId)),
      );
      for (final record in existing) {
        await AleraStores.chatCells.record(record.key).delete(txn);
      }
      for (var i = 0; i < cells.length; i++) {
        final cell = cells[i];
        final id = chatCellRecordId(chatId: chatId, seq: i);
        await AleraStores.chatCells.record(id).put(txn, <String, Object?>{
          'chatId': chatId,
          'seq': i,
          'cell': cell.toJson(),
        });
      }
    });
  }

  @override
  Future<List<TimelineCell>> loadCells(String chatId) async {
    final records = await AleraStores.chatCells.find(
      _db,
      finder: Finder(
        filter: Filter.equals('chatId', chatId),
        sortOrders: <SortOrder>[SortOrder('seq', true)],
      ),
    );
    final cells = <TimelineCell>[];
    for (final record in records) {
      final cellJson = record.value['cell'];
      if (cellJson is! Map) {
        continue;
      }
      try {
        cells.add(timelineCellFromJson(cellJson.cast<String, Object?>()));
      } catch (_) {
        // Skip malformed records — they are forward/backward incompatible
        // entries from a previous schema and should not crash hydration.
      }
    }
    return cells;
  }
}
