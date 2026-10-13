import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// A message the runtime holds until the running turn ends. Every client of
/// the chat sees the same queue and can cancel an entry before it is sent.
class const AgentChatQueueEntry({
  required final String queueId,
  required final String clientMessageId,
  required final String text,
  required final DateTime createdAt,
  final List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final queueId = agentChatJsonString(json['queueId']);
    if (queueId == null) {
      throw const FormatException('Agent chat queue entry has no queueId.');
    }
    return AgentChatQueueEntry(
      queueId: queueId,
      clientMessageId: agentChatJsonText(json['clientMessageId']),
      text: agentChatJsonText(json['text']),
      createdAt:
          agentChatJsonDate(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      attachments: <AgentChatAttachment>[
        for (final attachment in agentChatJsonList(json['attachments']))
          AgentChatAttachment.fromJson(attachment),
      ],
    );
  }
}

List<AgentChatQueueEntry> agentChatQueueFromJson(Object? value) =>
    <AgentChatQueueEntry>[
      for (final entry in agentChatJsonList(value))
        if (entry is Map) AgentChatQueueEntry.fromJson(entry),
    ];
