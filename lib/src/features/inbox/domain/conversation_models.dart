import 'package:alera/src/features/inbox/domain/inbox_models.dart';

/// Read-only view of what agents say to each other. Opening it never marks
/// anything read: an agent's read flag means it consumed the message.
class const ConversationThread({
  required final String threadId,
  required final String subject,
  required final String startedBy,
  required final List<String> participants,
  final String? workspaceId,
  final DateTime? createdAt,
  final DateTime? lastActivityAt,
  required final int lastSequence,
  required final int messageCount,
  required final bool group,
}) {
  factory ConversationThread.fromJson(Map<String, Object?> json) =>
      ConversationThread(
        threadId: _string(json['threadId']),
        subject: _string(json['subject']),
        startedBy: _string(json['startedBy']),
        participants: List<String>.unmodifiable(
          (json['participants'] is List
                  ? json['participants']! as List
                  : const [])
              .whereType<String>(),
        ),
        workspaceId: _optionalString(json['workspaceId']),
        createdAt: parseInboxTimestamp(json['createdAt']),
        lastActivityAt: parseInboxTimestamp(json['lastActivityAt']),
        lastSequence: _int(json['lastSequence']),
        messageCount: _int(json['messageCount']),
        group: json['group'] == true,
      );
}

class const ConversationPage({
  required final List<ConversationThread> items,
  final int? nextBefore,
  required final int revision,
}) {
  factory ConversationPage.fromJson(Map<String, Object?> json) =>
      ConversationPage(
        items: List<ConversationThread>.unmodifiable(
          _maps(json['items']).map(ConversationThread.fromJson),
        ),
        nextBefore: json['nextBefore'] is num
            ? (json['nextBefore']! as num).toInt()
            : null,
        revision: _int(json['revision']),
      );
}

class const ConversationMessage({
  required final String id,
  required final String from,
  required final String to,
  required final String type,
  required final String subject,
  required final String body,
  required final int sequence,
  final DateTime? createdAt,
}) {
  factory ConversationMessage.fromJson(Map<String, Object?> json) =>
      ConversationMessage(
        id: _string(json['id']),
        from: _string(json['from_handle']),
        to: _string(json['to_handle']),
        type: _string(json['type']),
        subject: _string(json['subject']),
        body: _string(json['body']),
        sequence: _int(json['sequence']),
        createdAt: parseInboxTimestamp(json['created_at']),
      );

  /// `decision_gate` reads as "decision gate".
  String get typeLabel => type.replaceAll('_', ' ');
}

class const ConversationDetail({
  required final String threadId,
  required final List<ConversationMessage> messages,
  required final int revision,
}) {
  factory ConversationDetail.fromJson(Map<String, Object?> json) =>
      ConversationDetail(
        threadId: _string(json['threadId']),
        messages: List<ConversationMessage>.unmodifiable(
          _maps(json['messages']).map(ConversationMessage.fromJson),
        ),
        revision: _int(json['revision']),
      );
}

String _string(Object? value) => value is String ? value : '';
String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
int _int(Object? value) => value is num ? value.toInt() : 0;
List<Map<String, Object?>> _maps(Object? value) => value is List
    ? value
          .whereType<Map<Object?, Object?>>()
          .map(Map<String, Object?>.from)
          .toList(growable: false)
    : const <Map<String, Object?>>[];
