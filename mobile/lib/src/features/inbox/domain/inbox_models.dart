import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// Inbox used by questions asked from the phone and the desktop, so both show
/// the same conversations.
const String userInboxAddress = 'ext:user';

/// Where a question stands, as the runtime derives it.
enum InboxQuestionStatus {
  pending('Pending'),
  received('Received'),
  delivered('Delivered'),
  expired('Expired'),
  answered('Answered'),
  cancelled('Cancelled'),
  unknown('Unknown');

  InboxQuestionStatus(this.label);

  final String label;

  static InboxQuestionStatus parse(String? value) => values.firstWhere(
    (status) => status.name == value && status != unknown,
    orElse: () => unknown,
  );

  /// Statuses a user filters by, in the order the list shows them.
  static const List<InboxQuestionStatus> filterable = <InboxQuestionStatus>[
    pending,
    delivered,
    received,
    answered,
    expired,
    cancelled,
  ];
}

enum InboxMessageKind {
  question,
  reply,
  message;

  static InboxMessageKind parse(String? value) =>
      values.firstWhere((kind) => kind.name == value, orElse: () => message);
}

/// How a question reaches the agent right now.
enum InboxDeliveryMode {
  /// Pasted into the agent when it finishes its turn.
  paste,

  /// Read by an active coordinator with `check`.
  check,

  /// No running agent with status hooks to deliver to.
  unavailable;

  static InboxDeliveryMode parse(String? value) => values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => unavailable,
  );
}

/// The runtime stores UTC timestamps as `YYYY-MM-DD HH:MM:SS`; ISO 8601 values
/// are accepted too.
DateTime? parseInboxTimestamp(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final trimmed = value.trim();
  final iso = trimmed.contains('T')
      ? trimmed
      : '${trimmed.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(iso)?.toUtc();
}

class const InboxSummaryEntry({
  required final String inbox,
  required final int threadCount,
  required final int pendingCount,
  required final int awaitingReplyCount,
  required final int unreadReplyCount,
  final DateTime? lastActivityAt,
}) {
  factory fromJson(Map<String, Object?> json) => InboxSummaryEntry(
    inbox: json.requiredString('inbox'),
    threadCount: _count(json['threadCount']),
    pendingCount: _count(json['pendingCount']),
    awaitingReplyCount: _count(json['awaitingReplyCount']),
    unreadReplyCount: _count(json['unreadReplyCount']),
    lastActivityAt: parseInboxTimestamp(json.optionalString('lastActivityAt')),
  );
}

/// Who asked: the surface the runtime saw the request come from.
class const InboxOrigin({
  required final String surface,
  final String? deviceName,
}) {
  factory fromJson(Map<String, Object?> json) => InboxOrigin(
    surface: json.optionalString('surface') ?? 'cli',
    deviceName: json.optionalString('deviceName'),
  );

  String get label => switch (surface) {
    'mobile' =>
      deviceName == null ? 'Alera mobile' : 'Alera mobile on $deviceName',
    'desktop' => 'Alera desktop',
    _ => 'Command line',
  };
}

/// How the recipient looked when the question was asked, so a thread keeps a
/// readable name after the terminal is gone.
class const InboxTarget({
  final String? agent,
  final String? tabTitle,
  final String? workspaceName,
}) {
  factory fromJson(Map<String, Object?> json) => InboxTarget(
    agent: json.optionalString('agent'),
    tabTitle: json.optionalString('tabTitle'),
    workspaceName: json.optionalString('workspaceName'),
  );
}

class const InboxThread({
  required final String threadId,
  required final String inbox,
  required final String recipient,
  required final String subject,
  required final InboxQuestionStatus status,
  required final int lastSequence,
  final String? workspaceId,
  final DateTime? createdAt,
  final DateTime? lastActivityAt,
  final int questionCount = 0,
  final int replyCount = 0,
  final int unreadReplyCount = 0,
  final InboxOrigin? origin,
  final InboxTarget target = const InboxTarget(),
}) {
  factory fromJson(Map<String, Object?> json) => InboxThread(
    threadId: json.requiredString('threadId'),
    inbox: json.requiredString('inbox'),
    recipient: json.requiredString('recipient'),
    subject: json.optionalString('subject') ?? '',
    status: InboxQuestionStatus.parse(json.optionalString('status')),
    lastSequence: _count(json['lastSequence']),
    workspaceId: json.optionalString('workspaceId'),
    createdAt: parseInboxTimestamp(json.optionalString('createdAt')),
    lastActivityAt: parseInboxTimestamp(json.optionalString('lastActivityAt')),
    questionCount: _count(json['questionCount']),
    replyCount: _count(json['replyCount']),
    unreadReplyCount: _count(json['unreadReplyCount']),
    origin: json['origin'] is Map
        ? InboxOrigin.fromJson(json.mapValue('origin'))
        : null,
    target: InboxTarget.fromJson(json.mapValue('target')),
  );

  /// Agent and terminal name for a row, falling back to the raw handle.
  String get recipientLabel {
    final parts = <String>[?target.agent, ?target.tabTitle];
    return parts.isEmpty ? recipient : parts.join(' · ');
  }
}

class const InboxMessage({
  required final String id,
  required final InboxMessageKind kind,
  required final String from,
  required final String to,
  required final String body,
  required final int sequence,
  final InboxQuestionStatus? status,
  final String subject = '',
  final bool read = false,
  final DateTime? createdAt,
  final DateTime? deliveredAt,
  final DateTime? expiresAt,
  final String? replyToId,
}) {
  factory fromJson(Map<String, Object?> json) {
    final message = json.mapValue('message');
    final status = json.optionalString('status');
    return InboxMessage(
      id: message.requiredString('id'),
      kind: InboxMessageKind.parse(json.optionalString('kind')),
      status: status == null ? null : InboxQuestionStatus.parse(status),
      from: message.optionalString('from_handle') ?? '',
      to: message.optionalString('to_handle') ?? '',
      subject: message.optionalString('subject') ?? '',
      body: message['body'] is String ? message['body']! as String : '',
      sequence: _count(message['sequence']),
      read: message['read'] == true,
      createdAt: parseInboxTimestamp(message.optionalString('created_at')),
      deliveredAt: parseInboxTimestamp(message.optionalString('delivered_at')),
      expiresAt: parseInboxTimestamp(message.optionalString('expires_at')),
      replyToId: message.optionalString('reply_to_id'),
    );
  }

  bool get isQuestion => kind == InboxMessageKind.question;
}

/// A terminal that can be asked, or the recipient of a thread.
class const InboxRecipient({
  required final String handle,
  required final InboxDeliveryMode deliveryMode,
  final bool sessionLive = false,
  final String? workspaceId,
  final String? tabId,
  final String? agent,
  final String? presence,
  final String? tabTitle,
}) {
  factory fromJson(Map<String, Object?> json) => InboxRecipient(
    handle: json.requiredString('handle'),
    deliveryMode: InboxDeliveryMode.parse(json.optionalString('deliveryMode')),
    sessionLive: json['sessionLive'] == true,
    workspaceId: json.optionalString('workspaceId'),
    tabId: json.optionalString('tabId'),
    agent: json.optionalString('agent'),
    presence: json.optionalString('presence'),
    tabTitle: json.optionalString('tabTitle'),
  );

  String get label {
    final parts = <String>[?agent, ?tabTitle];
    return parts.isEmpty ? handle : parts.join(' · ');
  }
}

class const InboxThreadDetail({
  required final InboxThread thread,
  required final List<InboxMessage> messages,
  final InboxRecipient? recipient,
  final int revision = 0,
}) {
  factory fromJson(Map<String, Object?> json) => InboxThreadDetail(
    revision: json['revision'] is int ? json['revision']! as int : 0,
    thread: InboxThread.fromJson(json.mapValue('thread')),
    messages: <InboxMessage>[
      for (final item in json.objectList('messages'))
        InboxMessage.fromJson(asJsonMap(item)),
    ],
    recipient: json['recipient'] is Map
        ? InboxRecipient.fromJson(json.mapValue('recipient'))
        : null,
  );

  /// The newest question, which a cancellation and the expiry hint refer to.
  InboxMessage? get latestQuestion =>
      messages.where((message) => message.isQuestion).lastOrNull;
}

class const InboxThreadPage({
  required final List<InboxThread> items,
  final int? nextBefore,
}) {
  factory fromJson(Map<String, Object?> json) => InboxThreadPage(
    items: <InboxThread>[
      for (final item in json.objectList('items'))
        InboxThread.fromJson(asJsonMap(item)),
    ],
    nextBefore: json['nextBefore'] is int ? json['nextBefore']! as int : null,
  );
}

class const InboxAskResult({
  required final String questionId,
  required final String threadId,
}) {
  factory fromJson(Map<String, Object?> json) {
    final questionId = json.requiredString('questionId');
    return InboxAskResult(
      questionId: questionId,
      threadId: json.optionalString('threadId') ?? questionId,
    );
  }
}

int _count(Object? value) => value is int ? value : 0;
