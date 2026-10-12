import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// Inbox used by questions asked from the phone and the desktop, so both show
/// the same conversations.
const String userInboxAddress = 'ext:user';

/// Where a question stands, as the runtime derives it.
enum InboxQuestionStatus {
  pending('Pending'),
  delivered('Delivered'),
  expired('Expired'),
  answered('Answered'),
  cancelled('Cancelled'),
  unknown('Unknown');

  InboxQuestionStatus(this.label);

  final String label;

  /// Older hosts report `received` when a coordinator read the question with
  /// `check`; `inboxV2` hosts count that as delivered.
  static InboxQuestionStatus parse(String? value) => value == 'received'
      ? delivered
      : values.firstWhere(
          (status) => status.name == value && status != unknown,
          orElse: () => unknown,
        );

  /// Statuses a user filters by, in the order the list shows them.
  static const List<InboxQuestionStatus> filterable = <InboxQuestionStatus>[
    pending,
    delivered,
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

/// How a question reaches the agent, as the host decided or would decide.
enum InboxDeliveryMode {
  /// Pasted into the agent's terminal right away.
  pastedNow('pasted_now'),

  /// Pasted when the agent finishes its turn.
  queuedAtTurnEnd('queued_at_turn_end'),

  /// Read by an active coordinator with `check`.
  check('check'),

  /// No running agent with status hooks to deliver to.
  unavailable('unavailable');

  InboxDeliveryMode(this.key);

  final String key;

  /// Hosts without `inboxV2` report `paste`, which always waited for the end
  /// of the turn.
  static InboxDeliveryMode parse(String? value) => value == 'paste'
      ? queuedAtTurnEnd
      : values.firstWhere(
          (mode) => mode.key == value,
          orElse: () => unavailable,
        );

  static InboxDeliveryMode? tryParse(String? value) =>
      value == null || value.isEmpty ? null : parse(value);

  /// Whether asking with [InboxDelivery.now] reaches the agent before its turn
  /// ends.
  bool get acceptsNow => this == pastedNow || this == check;
}

/// When the asker wants a question pasted. Sent only to `inboxV2` hosts.
enum InboxDelivery {
  now('now'),
  turnEnd('turnEnd');

  InboxDelivery(this.key);

  final String key;

  static InboxDelivery? tryParse(String? value) => switch (value) {
    'now' => now,
    'turnEnd' || 'turn_end' => turnEnd,
    _ => null,
  };
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
  final String? clientName,
}) {
  factory fromJson(Map<String, Object?> json) => InboxOrigin(
    surface: json.optionalString('surface') ?? 'cli',
    deviceName: json.optionalString('deviceName'),
    clientName:
        json.optionalString('clientName') ?? json.optionalString('clientId'),
  );

  String get label => switch (surface) {
    'mobile' =>
      deviceName == null ? 'Alera mobile' : 'Alera mobile on $deviceName',
    'desktop' => 'Alera desktop',
    'mcp' => clientName == null ? 'MCP client' : '$clientName (MCP)',
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
  final InboxDeliveryMode? deliveryMode,
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
    deliveryMode: InboxDeliveryMode.tryParse(
      json.optionalString('deliveryMode'),
    ),
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

  /// What the asker chose; absent before `inboxV2`.
  final InboxDelivery? delivery,
  final InboxDeliveryMode? deliveryMode,
}) {
  factory fromJson(Map<String, Object?> json) {
    final message = json.mapValue('message');
    final status = json.optionalString('status');
    // `inboxV2` hosts may report these beside the message row or inside it.
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
      deliveredAt: parseInboxTimestamp(
        json.optionalString('deliveredAt') ??
            message.optionalString('delivered_at'),
      ),
      expiresAt: parseInboxTimestamp(message.optionalString('expires_at')),
      replyToId: message.optionalString('reply_to_id'),
      delivery: InboxDelivery.tryParse(
        json.optionalString('delivery') ?? message.optionalString('delivery'),
      ),
      deliveryMode: InboxDeliveryMode.tryParse(
        json.optionalString('deliveryMode') ??
            message.optionalString('delivery_mode'),
      ),
    );
  }

  bool get isQuestion => kind == InboxMessageKind.question;

  /// Pasted as soon as it was asked. The host does not record the decision on
  /// older messages, so a delivery within the minute it was asked counts.
  bool get deliveredNow {
    if (deliveryMode case final mode?) {
      return mode == InboxDeliveryMode.pastedNow;
    }
    final asked = createdAt;
    final delivered = deliveredAt;
    return delivery == InboxDelivery.now &&
        asked != null &&
        delivered != null &&
        delivered.difference(asked) < const Duration(minutes: 1);
  }
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

  /// The agent takes input mid-turn, so `now` pastes even while it works.
  final bool acceptsQueuedInput = false,
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
    acceptsQueuedInput: json['acceptsQueuedInput'] == true,
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

/// What `inbox.ask` reports: the question, its thread and how it arrives.
class const InboxAskResult({
  required final String questionId,
  required final String threadId,
  final InboxDeliveryMode? deliveryMode,
}) {
  factory fromJson(Map<String, Object?> json) {
    final questionId = json.requiredString('questionId');
    return InboxAskResult(
      questionId: questionId,
      threadId: json.optionalString('threadId') ?? questionId,
      deliveryMode: InboxDeliveryMode.tryParse(
        json.optionalString('deliveryMode') ??
            json.mapValue('recipient').optionalString('deliveryMode'),
      ),
    );
  }
}

int _count(Object? value) => value is int ? value : 0;
