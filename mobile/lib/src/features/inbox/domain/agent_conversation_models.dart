import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';

/// A conversation between terminals, as the runtime groups it. Read only: the
/// phone never marks these messages read, because for an agent `read` means
/// it consumed the message.
class const AgentConversation({
  required final String threadId,
  required final String subject,
  required final String startedBy,
  required final List<String> participants,
  required final int lastSequence,
  final String? workspaceId,
  final DateTime? createdAt,
  final DateTime? lastActivityAt,
  final int messageCount = 0,
  final bool group = false,
}) {
  factory fromJson(Map<String, Object?> json) => AgentConversation(
    threadId: json.requiredString('threadId'),
    subject: json.optionalString('subject') ?? '',
    startedBy: json.optionalString('startedBy') ?? '',
    participants: json.stringList('participants'),
    lastSequence: json['lastSequence'] is int
        ? json['lastSequence']! as int
        : 0,
    workspaceId: json.optionalString('workspaceId'),
    createdAt: parseInboxTimestamp(json.optionalString('createdAt')),
    lastActivityAt: parseInboxTimestamp(json.optionalString('lastActivityAt')),
    messageCount: json['messageCount'] is int
        ? json['messageCount']! as int
        : 0,
    group: json['group'] == true,
  );
}

class const AgentConversationPage({
  required final List<AgentConversation> items,
  final int? nextBefore,
}) {
  factory fromJson(Map<String, Object?> json) => AgentConversationPage(
    items: <AgentConversation>[
      for (final item in json.objectList('items'))
        AgentConversation.fromJson(asJsonMap(item)),
    ],
    nextBefore: json['nextBefore'] is int ? json['nextBefore']! as int : null,
  );
}

/// One orchestration message in a conversation, in the runtime's snake_case
/// shape.
class const AgentConversationMessage({
  required final String id,
  required final String from,
  required final String to,
  required final String type,
  required final String body,
  required final int sequence,
  final String subject = '',
  final DateTime? createdAt,
}) {
  factory fromJson(Map<String, Object?> json) => AgentConversationMessage(
    id: json.requiredString('id'),
    from: json.optionalString('from_handle') ?? '',
    to: json.optionalString('to_handle') ?? '',
    type: json.optionalString('type') ?? 'status',
    body: json['body'] is String ? json['body']! as String : '',
    sequence: json['sequence'] is int ? json['sequence']! as int : 0,
    subject: json.optionalString('subject') ?? '',
    createdAt: parseInboxTimestamp(json.optionalString('created_at')),
  );

  /// The message type in words, such as `Decision Gate`.
  String get typeLabel => type
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class const AgentConversationDetail({
  required final String threadId,
  required final List<AgentConversationMessage> messages,
}) {
  factory fromJson(Map<String, Object?> json) => AgentConversationDetail(
    threadId: json.requiredString('threadId'),
    messages: <AgentConversationMessage>[
      for (final item in json.objectList('messages'))
        AgentConversationMessage.fromJson(asJsonMap(item)),
    ],
  );
}

/// A readable name for a terminal handle: the agent and tab title the runtime
/// reports for it, else the handle itself.
String agentConversationHandleLabel(
  String handle,
  Map<String, String> labels,
) => labels[handle] ?? handle;
