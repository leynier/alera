import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';

/// Why a chat is worth a notice.
enum ChatAttentionNotice { needsInput, failed, done }

/// Turns successive chat snapshots into notices, once per transition. A chat
/// seen for the first time only records its level, so whatever the runtime
/// already held when the app connected never replays as a burst. The same
/// notice for the same chat stays quiet for [cooldown], since an agent
/// re-enters waiting once per approval.
final class ChatAttentionTransitions {
  ChatAttentionTransitions({
    required this._now,
    this.cooldown = const Duration(seconds: 60),
  });

  final DateTime Function() _now;
  final Duration cooldown;
  final Map<String, ChatAttentionLevel> _levels =
      <String, ChatAttentionLevel>{};
  final Map<(String, ChatAttentionNotice), DateTime> _sent =
      <(String, ChatAttentionNotice), DateTime>{};

  /// The notices [entries] owe since the previous call. Children report
  /// through their parent, so chats in [children] never notify.
  List<(ChatAttentionEntry, ChatAttentionNotice)> next(
    Map<String, ChatAttentionEntry> entries, {
    Set<String> children = const <String>{},
  }) {
    final now = _now();
    final notices = <(ChatAttentionEntry, ChatAttentionNotice)>[];
    _levels.removeWhere((chatId, _) => !entries.containsKey(chatId));
    for (final entry in entries.values) {
      final previous = _levels[entry.chatId];
      final level = entry.level;
      _levels[entry.chatId] = level;
      if (previous == null || previous == level) continue;
      final notice = switch (level) {
        ChatAttentionLevel.needsInput => ChatAttentionNotice.needsInput,
        ChatAttentionLevel.failed => ChatAttentionNotice.failed,
        ChatAttentionLevel.unread ||
        ChatAttentionLevel.waitingOnTasks ||
        ChatAttentionLevel.idle when previous == ChatAttentionLevel.working =>
          ChatAttentionNotice.done,
        _ => null,
      };
      if (notice == null || children.contains(entry.chatId)) continue;
      final key = (entry.chatId, notice);
      final sent = _sent[key];
      if (sent != null && now.difference(sent) < cooldown) continue;
      _sent[key] = now;
      notices.add((entry, notice));
    }
    return notices;
  }
}

/// The notice as a sentence, for a toast and an OS notification body.
String chatAttentionNoticeMessage(
  ChatAttentionEntry entry,
  ChatAttentionNotice notice,
) {
  final title = entry.title.trim().isEmpty ? 'An agent chat' : entry.title;
  return switch (notice) {
    ChatAttentionNotice.needsInput => '$title is waiting for you.',
    ChatAttentionNotice.failed => '$title stopped with an error.',
    ChatAttentionNotice.done => '$title finished.',
  };
}
