import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';

typedef InboxCall = ({String type, Map<String, Object?> payload});

Map<String, Object?> inboxThreadJson({
  String threadId = 'msg_1',
  String inbox = 'ext:user',
  String status = 'delivered',
  String subject = 'Which tests cover login?',
  int unread = 0,
  String? workspaceId = 'ws-1',
  int lastSequence = 12,
}) => <String, Object?>{
  'threadId': threadId,
  'inbox': inbox,
  'recipient': 'claude-term',
  'workspaceId': workspaceId,
  'subject': subject,
  'createdAt': '2026-10-06 10:00:00',
  'lastActivityAt': '2026-10-06 10:05:00',
  'lastSequence': lastSequence,
  'status': status,
  'questionCount': 1,
  'replyCount': unread,
  'unreadReplyCount': unread,
  'origin': <String, Object?>{'surface': 'mobile', 'deviceName': 'Pixel'},
  'target': <String, Object?>{
    'agent': 'claude',
    'tabTitle': 'Fix Login',
    'workspaceName': 'auth',
  },
};

Map<String, Object?> inboxMessageJson({
  String id = 'msg_1',
  String kind = 'question',
  String? status = 'pending',
  String from = 'ext:user',
  String to = 'claude-term',
  String body = 'Which tests cover login?',
  int sequence = 10,
  String? replyToId,
  String? expiresAt = '2099-01-01 00:00:00',
}) => <String, Object?>{
  'kind': kind,
  'status': ?status,
  'message': <String, Object?>{
    'id': id,
    'from_handle': from,
    'to_handle': to,
    'subject': 'Which tests cover login?',
    'body': body,
    'type': 'decision_gate',
    'priority': 'high',
    'read': false,
    'sequence': sequence,
    'created_at': '2026-10-06 10:00:00',
    'state': 'queued',
    'expires_at': expiresAt,
    'reply_to_id': replyToId,
  },
};

Map<String, Object?> inboxTargetJson({
  String handle = 'claude-term',
  String agent = 'claude',
  String workspaceId = 'ws-1',
  String deliveryMode = 'paste',
  String tabTitle = 'Fix Login',
}) => <String, Object?>{
  'handle': handle,
  'sessionLive': true,
  'workspaceId': workspaceId,
  'tabId': 'tab-$handle',
  'agent': agent,
  'presence': 'working',
  'deliveryMode': deliveryMode,
  'tabTitle': tabTitle,
};

Map<String, Object?> agentConversationJson({
  String threadId = 'thread_1',
  String subject = 'Split the migration',
  List<String> participants = const <String>['claude-term', 'codex-term'],
  String workspaceId = 'ws-1',
  int messageCount = 2,
  bool group = false,
  int lastSequence = 40,
}) => <String, Object?>{
  'threadId': threadId,
  'subject': subject,
  'startedBy': participants.first,
  'participants': participants,
  'workspaceId': workspaceId,
  'createdAt': '2026-10-06 09:00:00',
  'lastActivityAt': '2026-10-06 09:30:00',
  'lastSequence': lastSequence,
  'messageCount': messageCount,
  'group': group,
};

Map<String, Object?> agentMessageJson({
  String id = 'thread_1',
  String from = 'claude-term',
  String to = 'codex-term',
  String type = 'decision_gate',
  String body = 'Can you take the schema half?',
  int sequence = 30,
}) => <String, Object?>{
  'id': id,
  'from_handle': from,
  'to_handle': to,
  'subject': 'Split the migration',
  'body': body,
  'type': type,
  'priority': 'normal',
  'thread_id': id == 'thread_1' ? null : 'thread_1',
  'read': true,
  'sequence': sequence,
  'created_at': '2026-10-06 09:00:00',
  'state': 'read',
};

/// Paired runtime double for the Inbox screens. Responses are the JSON the
/// runtime sends.
class FakeInboxClient implements MobileInboxClient {
  FakeInboxClient({this.supportsInbox = true});

  @override
  bool supportsInbox;
  List<Map<String, Object?>> threads = <Map<String, Object?>>[
    inboxThreadJson(),
  ];
  Map<String, List<Map<String, Object?>>> messages =
      <String, List<Map<String, Object?>>>{
        'msg_1': <Map<String, Object?>>[inboxMessageJson()],
      };
  List<Map<String, Object?>> targets = <Map<String, Object?>>[
    inboxTargetJson(),
    inboxTargetJson(handle: 'codex-term', agent: 'codex', tabTitle: 'Review'),
  ];
  List<WorkspaceSummary> workspaces = <WorkspaceSummary>[];
  List<Map<String, Object?>> conversations = <Map<String, Object?>>[
    agentConversationJson(),
    agentConversationJson(
      threadId: 'thread_2',
      subject: 'Status to everyone',
      participants: <String>['claude-term', 'codex-term', 'shell-term'],
      workspaceId: 'ws-2',
      messageCount: 3,
      group: true,
    ),
  ];
  List<Map<String, Object?>> conversationMessages = <Map<String, Object?>>[
    agentMessageJson(),
    agentMessageJson(
      id: 'msg_reply',
      from: 'codex-term',
      to: 'claude-term',
      type: 'status',
      body: 'Taking it.',
      sequence: 40,
    ),
  ];
  Object? failure;

  /// Inbox revision the runtime reports; acknowledging a thread moves it.
  int revision = 3;
  final List<InboxCall> calls = <InboxCall>[];
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();

  Iterable<InboxCall> callsOf(String type) =>
      calls.where((call) => call.type == type);

  void emit(String name, [Map<String, Object?> payload = const {}]) =>
      _events.add(MobileRuntimeEvent(name, payload));

  Future<void> dispose() => _events.close();

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async => workspaces;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add((type: type, payload: payload));
    if (failure case final error?) throw error;
    return switch (type) {
      'inbox.summary' => <String, Object?>{
        'kind': 'inboxes',
        'items': <Object?>[
          <String, Object?>{
            'inbox': 'ext:user',
            'threadCount': threads.length,
            'pendingCount': 0,
            'awaitingReplyCount': 1,
            'unreadReplyCount': 0,
            'lastActivityAt': '2026-10-06 10:05:00',
          },
        ],
        'revision': 3,
      },
      'inbox.threads' => _page(
        'inboxThreads',
        threads.where(
          (thread) =>
              (payload['inbox'] == null ||
                  thread['inbox'] == payload['inbox']) &&
              (payload['status'] == null ||
                  thread['status'] == payload['status']),
        ),
        payload,
      ),
      'inbox.markRead' => _markRead(payload),
      'inbox.thread' => <String, Object?>{
        'thread': threads.firstWhere(
          (thread) => thread['threadId'] == payload['threadId'],
        ),
        'messages': messages[payload['threadId']] ?? const <Object?>[],
        'recipient': inboxTargetJson(),
        'revision': revision,
      },
      'inbox.targets' => <String, Object?>{
        'kind': 'inboxTargets',
        'items': <Object?>[
          for (final target in targets)
            if (payload['workspaceId'] == null ||
                target['workspaceId'] == payload['workspaceId'])
              target,
        ],
      },
      'inbox.ask' => _ask(payload),
      'inbox.purge' => <String, Object?>{'deleted': 2, 'revision': 5},
      'inbox.conversations' => _page(
        'conversations',
        conversations.where(
          (conversation) =>
              payload['workspaceId'] == null ||
              conversation['workspaceId'] == payload['workspaceId'],
        ),
        payload,
      ),
      'inbox.conversation' => <String, Object?>{
        'threadId': payload['threadId'],
        'messages': conversationMessages,
        'revision': 7,
      },
      _ => <String, Object?>{'revision': 4},
    };
  }

  /// The runtime's rule: a follow-up keeps its thread's inbox, so naming a
  /// different one is refused.
  Map<String, Object?> _ask(Map<String, Object?> payload) {
    final threadId = payload['threadId'];
    if (threadId != null) {
      final root = threads.where((thread) => thread['threadId'] == threadId);
      final inbox = payload['inbox'];
      if (root.isNotEmpty && inbox != null && inbox != root.first['inbox']) {
        throw StateError(
          'A follow-up must continue a question this inbox sent to the same recipient',
        );
      }
    }
    return <String, Object?>{
      'questionId': 'msg_new',
      'threadId': threadId ?? 'msg_new',
      'message': <String, Object?>{'id': 'msg_new'},
      'recipient': inboxTargetJson(),
      'revision': 4,
    };
  }

  /// Most recent activity first, `before` excludes `lastSequence >= before`,
  /// and `nextBefore` is the last item's `lastSequence` when more remain.
  Map<String, Object?> _page(
    String kind,
    Iterable<Map<String, Object?>> items,
    Map<String, Object?> payload,
  ) {
    final before = payload['before'];
    final limit = payload['limit'] is int ? payload['limit']! as int : 100;
    final sorted =
        items
            .where(
              (item) =>
                  before is! int || (item['lastSequence']! as int) < before,
            )
            .toList()
          ..sort(
            (a, b) => (b['lastSequence']! as int).compareTo(
              a['lastSequence']! as int,
            ),
          );
    final page = sorted.take(limit).toList();
    return <String, Object?>{
      'kind': kind,
      'items': page,
      'nextBefore': sorted.length > limit ? page.last['lastSequence'] : null,
      'revision': 3,
    };
  }

  /// Like the runtime: replies of the thread become read and the revision
  /// moves only when something changed.
  Map<String, Object?> _markRead(Map<String, Object?> payload) {
    var marked = 0;
    for (final thread in threads) {
      if (thread['threadId'] == payload['threadId']) {
        marked = thread['unreadReplyCount']! as int;
        thread['unreadReplyCount'] = 0;
      }
    }
    if (marked > 0) revision++;
    return <String, Object?>{'marked': marked, 'revision': revision};
  }
}
