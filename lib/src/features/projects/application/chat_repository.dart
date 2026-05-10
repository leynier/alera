import 'package:alera/src/features/projects/domain/chat_message.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';

abstract interface class ChatRepository {
  Future<List<ChatSummary>> listByProject(String projectId);

  Stream<List<ChatSummary>> watchByProject(String projectId);

  Future<ChatSummary?> findById(String chatId);

  Future<ChatSummary> upsert(ChatSummary chat);

  Future<void> remove(String chatId, {bool cascadeMessages = true});

  Future<List<ChatMessage>> loadMessages(String chatId);

  Future<int> nextSeq(String chatId);

  Future<ChatMessage> appendMessage(ChatMessage message);

  /// Replaces the persisted snapshot of timeline cells for [chatId]. Pass an
  /// empty list to clear the snapshot entirely.
  Future<void> replaceCells(String chatId, List<TimelineCell> cells);

  /// Loads the persisted timeline cells in their original insertion order.
  Future<List<TimelineCell>> loadCells(String chatId);
}
