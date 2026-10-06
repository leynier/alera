import 'dart:async';

import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/inbox/infra/runtime_inbox_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_riverpod/misc.dart';

/// Runtime client double that answers `inbox.*` from canned payloads.
class InboxTestClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  final StreamController<RuntimeHostEvent> events =
      StreamController<RuntimeHostEvent>.broadcast();
  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];
  final Map<String, Object? Function(Map<String, Object?>)> handlers =
      <String, Object? Function(Map<String, Object?>)>{};
  bool supported = true;

  void respond(String type, Object? payload) => handlers[type] = (_) => payload;

  void emit(String name) => events.add(RuntimeHostEvent(name, const {}));

  List<Map<String, Object?>> callsTo(String type) => <Map<String, Object?>>[
    for (final (name, payload) in calls)
      if (name == type) payload,
  ];

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capability == aleraRuntimeHostInboxCapability && supported;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add((type, payload));
    final handler = handlers[type];
    if (handler == null) return const <String, Object?>{};
    return handler(payload);
  }
}

/// Real repository over the test client, so payload parsing is exercised.
List<Override> inboxClientOverrides(InboxTestClient client) => <Override>[
  inboxRepositoryProvider.overrideWith((ref) {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 1),
      maxDelay: const Duration(milliseconds: 50),
    );
    ref.onDispose(coalescer.dispose);
    return RuntimeInboxRepository(client, coalescer);
  }),
];

Map<String, Object?> inboxThreadJson({
  String threadId = 'msg_q1',
  String status = 'delivered',
  String subject = 'Migration risk',
  int unread = 0,
  String inbox = 'ext:user',
}) => <String, Object?>{
  'threadId': threadId,
  'inbox': inbox,
  'recipient': 'term-1',
  'workspaceId': 'ws-1',
  'subject': subject,
  'createdAt': '2026-10-06 10:00:00',
  'lastActivityAt': '2026-10-06 10:05:00',
  'lastSequence': 12,
  'status': status,
  'questionCount': 1,
  'replyCount': unread,
  'unreadReplyCount': unread,
  'origin': <String, Object?>{'surface': 'mobile', 'deviceName': 'Pixel'},
  'target': <String, Object?>{
    'agent': 'claude',
    'tabTitle': 'Fix Login',
    'workspaceName': 'Auth',
  },
};

Map<String, Object?> inboxMessageJson({
  required String kind,
  required String id,
  required String body,
  String? status,
  bool read = false,
  String from = 'ext:user',
  String to = 'term-1',
  String? expiresAt,
}) => <String, Object?>{
  'kind': kind,
  'status': ?status,
  'message': <String, Object?>{
    'id': id,
    'from_handle': from,
    'to_handle': to,
    'subject': 'Migration risk',
    'body': body,
    'read': read,
    'sequence': id == 'msg_q1' ? 10 : 12,
    'created_at': '2026-10-06 10:00:00',
    'expires_at': ?expiresAt,
  },
};

Map<String, Object?> inboxDetailJson({
  String status = 'delivered',
  List<Map<String, Object?>>? messages,
  String deliveryMode = 'paste',
  bool sessionLive = true,
}) => <String, Object?>{
  'thread': inboxThreadJson(status: status),
  'messages':
      messages ??
      <Map<String, Object?>>[
        inboxMessageJson(
          kind: 'question',
          id: 'msg_q1',
          body: 'What could break?',
          status: status,
        ),
      ],
  'recipient': <String, Object?>{
    'handle': 'term-1',
    'sessionLive': sessionLive,
    'workspaceId': 'ws-1',
    'agent': 'claude',
    'deliveryMode': deliveryMode,
  },
  'revision': 3,
};
