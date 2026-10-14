import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';

/// A row of `agentChat.list`: enough to label and open a chat without its
/// timeline.
class const AgentChatSummary({
  required final String chatId,
  required final String workspaceId,
  required final String title,
  required final String provider,
  required final String providerInstanceId,
  required final AgentChatSessionStatus status,
  required final DateTime updatedAt,
  final String? tabId,
  final String? model,
  final int cursor = 0,
  final bool archived = false,
  final bool busy = false,
  final int pendingRequestCount = 0,
  final int openChildTaskCount = 0,
  final bool childNeedsInput = false,
  final bool unread = false,
  final int readCursor = 0,

  /// The chat whose first delegation handed work to this one.
  final String? parentChatId,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final chatId = agentChatJsonString(json['chatId']);
    if (chatId == null) {
      throw const FormatException('Agent chat summary has no chatId.');
    }
    return AgentChatSummary(
      chatId: chatId,
      workspaceId: agentChatJsonText(json['workspaceId']),
      title: agentChatJsonText(json['title']),
      provider: agentChatJsonText(json['provider']),
      providerInstanceId: agentChatJsonText(json['providerInstanceId']),
      status: AgentChatSessionStatus.fromJson(json['status']),
      updatedAt:
          agentChatJsonDate(json['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      tabId: agentChatJsonString(json['tabId']),
      model: agentChatJsonString(json['model']),
      cursor: agentChatJsonInt(json['cursor']) ?? 0,
      archived: agentChatJsonBool(json['archived']),
      busy: agentChatJsonBool(json['busy']),
      pendingRequestCount: agentChatJsonInt(json['pendingRequestCount']) ?? 0,
      openChildTaskCount: agentChatJsonInt(json['openChildTaskCount']) ?? 0,
      childNeedsInput: agentChatJsonBool(json['childNeedsInput']),
      unread: agentChatJsonBool(json['unread']),
      readCursor: agentChatJsonInt(json['readCursor']) ?? 0,
      parentChatId: agentChatJsonString(json['parentChatId']),
    );
  }
}

List<AgentChatSummary> agentChatSummariesFromJson(Object? value) {
  final json = agentChatJsonMap(value);
  final list = value is List ? value : agentChatJsonList(json['chats']);
  return <AgentChatSummary>[
    for (final chat in list)
      if (chat is Map) AgentChatSummary.fromJson(chat),
  ];
}
