/// Read models for the inbox: questions sent to agents from an `ext:`
/// address (the CLI, this app, a paired phone) and the replies they got.
library;

/// Inbox used by the desktop and mobile apps, so both show one conversation.
const String inboxUserAddress = 'ext:user';

enum InboxQuestionStatus {
  pending('pending', 'Pending'),
  received('received', 'Received'),
  delivered('delivered', 'Delivered'),
  expired('expired', 'Expired'),
  answered('answered', 'Answered'),
  cancelled('cancelled', 'Cancelled');

  InboxQuestionStatus(this.key, this.label);

  final String key;
  final String label;

  static InboxQuestionStatus parse(Object? value) => values.firstWhere(
    (status) => status.key == value,
    orElse: () => InboxQuestionStatus.pending,
  );

  /// Still waiting for the agent to read or answer.
  bool get open => this == pending || this == received || this == delivered;
}

enum InboxMessageKind {
  question,
  reply,
  message;

  static InboxMessageKind parse(Object? value) => values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => InboxMessageKind.message,
  );
}

/// How a question reaches the agent right now.
enum InboxDeliveryMode {
  /// Pasted when the agent finishes its turn.
  paste,

  /// The agent coordinates a run and reads questions with `check`.
  check,

  /// No running agent reports its turns, so nothing will be pasted.
  unavailable;

  static InboxDeliveryMode parse(Object? value) => values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => InboxDeliveryMode.unavailable,
  );
}

String _string(Object? value) => value is String ? value : '';
String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
int _int(Object? value) => value is num ? value.toInt() : 0;
Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};
List<Map<String, Object?>> _maps(Object? value) => value is List
    ? List<Map<String, Object?>>.unmodifiable(
        value.whereType<Map<Object?, Object?>>().map(Map<String, Object?>.from),
      )
    : const <Map<String, Object?>>[];

/// Host timestamps are UTC `YYYY-MM-DD HH:MM:SS` (SQLite) or RFC 3339.
DateTime? parseInboxTimestamp(Object? value) {
  final raw = _optionalString(value);
  if (raw == null) return null;
  final normalized = raw.contains('T') ? raw : '${raw.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(normalized)?.toUtc();
}

/// Where a question was asked from, recorded by the host from the connection.
class const InboxOrigin({
  required final String surface,
  final String? deviceName,
}) {
  factory InboxOrigin.fromJson(Map<String, Object?> json) => InboxOrigin(
    surface: _optionalString(json['surface']) ?? 'cli',
    deviceName: _optionalString(json['deviceName']),
  );

  String get label => switch (surface) {
    'desktop' => 'Alera desktop',
    'mobile' =>
      deviceName == null ? 'Alera mobile' : 'Alera mobile, $deviceName',
    _ => 'CLI',
  };
}

/// How the recipient looked when the question was asked.
class const InboxTargetSnapshot({
  final String? agent,
  final String? tabTitle,
  final String? workspaceName,
}) {
  factory InboxTargetSnapshot.fromJson(Map<String, Object?> json) =>
      InboxTargetSnapshot(
        agent: _optionalString(json['agent']),
        tabTitle: _optionalString(json['tabTitle']),
        workspaceName: _optionalString(json['workspaceName']),
      );
}

class const InboxSummaryEntry({
  required final String inbox,
  required final int threadCount,
  required final int pendingCount,
  required final int awaitingReplyCount,
  required final int unreadReplyCount,
  final DateTime? lastActivityAt,
}) {
  factory InboxSummaryEntry.fromJson(Map<String, Object?> json) =>
      InboxSummaryEntry(
        inbox: _string(json['inbox']),
        threadCount: _int(json['threadCount']),
        pendingCount: _int(json['pendingCount']),
        awaitingReplyCount: _int(json['awaitingReplyCount']),
        unreadReplyCount: _int(json['unreadReplyCount']),
        lastActivityAt: parseInboxTimestamp(json['lastActivityAt']),
      );
}

class const InboxSummary({
  required final List<InboxSummaryEntry> inboxes,
  required final int revision,
}) {
  factory InboxSummary.fromJson(Map<String, Object?> json) => InboxSummary(
    inboxes: List<InboxSummaryEntry>.unmodifiable(
      _maps(json['items']).map(InboxSummaryEntry.fromJson),
    ),
    revision: _int(json['revision']),
  );

  int get unreadReplyCount =>
      inboxes.fold(0, (total, entry) => total + entry.unreadReplyCount);
}

class const InboxThread({
  required final String threadId,
  required final String inbox,
  required final String recipient,
  final String? workspaceId,
  required final String subject,
  final DateTime? createdAt,
  final DateTime? lastActivityAt,
  required final int lastSequence,
  required final InboxQuestionStatus status,
  required final int questionCount,
  required final int replyCount,
  required final int unreadReplyCount,
  final InboxOrigin? origin,
  final InboxTargetSnapshot target = const InboxTargetSnapshot(),
}) {
  factory InboxThread.fromJson(Map<String, Object?> json) => InboxThread(
    threadId: _string(json['threadId']),
    inbox: _string(json['inbox']),
    recipient: _string(json['recipient']),
    workspaceId: _optionalString(json['workspaceId']),
    subject: _string(json['subject']),
    createdAt: parseInboxTimestamp(json['createdAt']),
    lastActivityAt: parseInboxTimestamp(json['lastActivityAt']),
    lastSequence: _int(json['lastSequence']),
    status: InboxQuestionStatus.parse(json['status']),
    questionCount: _int(json['questionCount']),
    replyCount: _int(json['replyCount']),
    unreadReplyCount: _int(json['unreadReplyCount']),
    origin: json['origin'] is Map
        ? InboxOrigin.fromJson(_map(json['origin']))
        : null,
    target: InboxTargetSnapshot.fromJson(_map(json['target'])),
  );
}

class const InboxThreadPage({
  required final List<InboxThread> items,
  final int? nextBefore,
  required final int revision,
}) {
  factory InboxThreadPage.fromJson(Map<String, Object?> json) =>
      InboxThreadPage(
        items: List<InboxThread>.unmodifiable(
          _maps(json['items']).map(InboxThread.fromJson),
        ),
        nextBefore: json['nextBefore'] is num
            ? (json['nextBefore']! as num).toInt()
            : null,
        revision: _int(json['revision']),
      );
}

/// One row of the thread: an orchestration message seen from the inbox.
class const InboxMessage({
  required final String id,
  required final InboxMessageKind kind,
  final InboxQuestionStatus? status,
  required final String from,
  required final String to,
  required final String subject,
  required final String body,
  required final bool read,
  required final int sequence,
  final DateTime? createdAt,
  final DateTime? deliveredAt,
  final DateTime? expiresAt,
  final String? replyToId,
}) {
  factory InboxMessage.fromJson(Map<String, Object?> json) {
    final message = _map(json['message']);
    final status = json['status'];
    return InboxMessage(
      id: _string(message['id']),
      kind: InboxMessageKind.parse(json['kind']),
      status: status == null ? null : InboxQuestionStatus.parse(status),
      from: _string(message['from_handle']),
      to: _string(message['to_handle']),
      subject: _string(message['subject']),
      body: _string(message['body']),
      read: message['read'] == true,
      sequence: _int(message['sequence']),
      createdAt: parseInboxTimestamp(message['created_at']),
      deliveredAt: parseInboxTimestamp(message['delivered_at']),
      expiresAt: parseInboxTimestamp(message['expires_at']),
      replyToId: _optionalString(message['reply_to_id']),
    );
  }
}

/// A terminal that can be asked, as the host sees it now.
class const InboxRecipient({
  required final String handle,
  required final bool sessionLive,
  final String? workspaceId,
  final String? tabId,
  final String? agent,
  final String? presence,
  required final InboxDeliveryMode deliveryMode,
  final String? tabTitle,
}) {
  factory InboxRecipient.fromJson(Map<String, Object?> json) => InboxRecipient(
    handle: _string(json['handle']),
    sessionLive: json['sessionLive'] == true,
    workspaceId: _optionalString(json['workspaceId']),
    tabId: _optionalString(json['tabId']),
    agent: _optionalString(json['agent']),
    presence: _optionalString(json['presence']),
    deliveryMode: InboxDeliveryMode.parse(json['deliveryMode']),
    tabTitle: _optionalString(json['tabTitle']),
  );
}

class const InboxThreadDetail({
  required final InboxThread thread,
  required final List<InboxMessage> messages,
  required final InboxRecipient recipient,
  required final int revision,
}) {
  factory InboxThreadDetail.fromJson(Map<String, Object?> json) =>
      InboxThreadDetail(
        thread: InboxThread.fromJson(_map(json['thread'])),
        messages: List<InboxMessage>.unmodifiable(
          _maps(json['messages']).map(InboxMessage.fromJson),
        ),
        recipient: InboxRecipient.fromJson(_map(json['recipient'])),
        revision: _int(json['revision']),
      );

  /// The question a follow-up or a cancellation acts on.
  InboxMessage? get latestQuestion => messages
      .where((message) => message.kind == InboxMessageKind.question)
      .lastOrNull;
}

List<InboxRecipient> parseInboxTargets(Map<String, Object?> json) =>
    List<InboxRecipient>.unmodifiable(
      _maps(json['items']).map(InboxRecipient.fromJson),
    );

/// A new question, or a follow-up when [threadId] is set.
class const InboxAskRequest({
  required final String body,
  final String? inbox,
  final String? to,
  final String? threadId,
  final String? subject,
  final Duration? expiresIn,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    'body': body,
    'inbox': ?inbox,
    'to': ?to,
    'threadId': ?threadId,
    if (subject != null && subject!.trim().isNotEmpty) 'subject': subject,
    if (expiresIn != null) 'expiresInMs': expiresIn!.inMilliseconds,
  };
}
