import 'package:alera/src/features/projects/domain/chat_summary.dart';

enum ChatRecencyBucket { today, yesterday, thisWeek, older }

class ChatGroup {
  const ChatGroup({required this.bucket, required this.chats});

  final ChatRecencyBucket bucket;
  final List<ChatSummary> chats;
}

/// Agrupa los chats por proximidad temporal de `updatedAt` relativo a `now`.
/// Devuelve los buckets en orden Today -> Yesterday -> This week -> Older,
/// omitiendo los buckets vacíos. Dentro de cada bucket preserva el orden de
/// entrada (que asumimos descendente por `updatedAt`).
List<ChatGroup> groupChatsByRecency(
  List<ChatSummary> chats, {
  required DateTime now,
}) {
  if (chats.isEmpty) {
    return const <ChatGroup>[];
  }
  final localNow = now.toLocal();
  final startOfToday = DateTime(localNow.year, localNow.month, localNow.day);
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
  final startOfWeek = startOfToday.subtract(const Duration(days: 7));

  final today = <ChatSummary>[];
  final yesterday = <ChatSummary>[];
  final thisWeek = <ChatSummary>[];
  final older = <ChatSummary>[];

  for (final chat in chats) {
    final local = chat.updatedAt.toLocal();
    if (!local.isBefore(startOfToday)) {
      today.add(chat);
    } else if (!local.isBefore(startOfYesterday)) {
      yesterday.add(chat);
    } else if (!local.isBefore(startOfWeek)) {
      thisWeek.add(chat);
    } else {
      older.add(chat);
    }
  }

  return <ChatGroup>[
    if (today.isNotEmpty)
      ChatGroup(bucket: ChatRecencyBucket.today, chats: today),
    if (yesterday.isNotEmpty)
      ChatGroup(bucket: ChatRecencyBucket.yesterday, chats: yesterday),
    if (thisWeek.isNotEmpty)
      ChatGroup(bucket: ChatRecencyBucket.thisWeek, chats: thisWeek),
    if (older.isNotEmpty)
      ChatGroup(bucket: ChatRecencyBucket.older, chats: older),
  ];
}

String chatRecencyBucketLabel(ChatRecencyBucket bucket) {
  switch (bucket) {
    case ChatRecencyBucket.today:
      return 'Today';
    case ChatRecencyBucket.yesterday:
      return 'Yesterday';
    case ChatRecencyBucket.thisWeek:
      return 'This week';
    case ChatRecencyBucket.older:
      return 'Older';
  }
}
