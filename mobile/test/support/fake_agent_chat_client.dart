import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

typedef AgentChatCall = ({String type, Map<String, Object?> payload});
typedef AgentChatHandler = FutureOr<Map<String, Object?>> Function(
  Map<String, Object?> payload,
);

/// The paired runtime as agent chats see it, answering `agentChat.*` verbs
/// from per-verb handlers and letting a test push runtime events.
class FakeAgentChatClient implements MobileAgentChatClient {
  FakeAgentChatClient({Set<String>? capabilities})
    : runtimeCapabilities = capabilities ?? <String>{'agentChatV1'};

  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final List<AgentChatCall> calls = <AgentChatCall>[];
  final Map<String, AgentChatHandler> handlers = <String, AgentChatHandler>{};

  @override
  final Set<String> runtimeCapabilities;

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add((type: type, payload: payload));
    final handler = handlers[type];
    if (handler == null) throw StateError('Unexpected request $type');
    return handler(payload);
  }

  List<Map<String, Object?>> payloadsOf(String type) => <Map<String, Object?>>[
    for (final call in calls)
      if (call.type == type) call.payload,
  ];

  void emit(String name, Map<String, Object?> payload) =>
      _events.add(MobileRuntimeEvent(name, payload));

  /// A change event for `chat-1` at [cursor].
  void emitChange(int cursor, Map<String, Object?> delta) =>
      emit('agentChatChanged', <String, Object?>{
        'chatId': 'chat-1',
        'workspaceId': 'workspace-1',
        'cursor': cursor,
        'delta': delta,
      });

  /// The connection ends, as a dead socket closes the client's event lane.
  Future<void> disconnect() => _events.close();
}

const String _at = '2026-10-12T10:00:00Z';

Map<String, Object?> agentChatSession({
  String status = 'ready',
  String? activeTurnId,
  String? model = 'gpt-5',
  bool interrupt = true,
  bool attachments = false,
}) => <String, Object?>{
  'status': status,
  'model': ?model,
  'runtimeMode': 'approval-required',
  'interactionMode': 'default',
  'activeTurnId': ?activeTurnId,
  'cwd': '/repo',
  'capabilities': <String, Object?>{
    'interrupt': interrupt,
    'approvals': true,
    'userInput': true,
    'attachments': attachments,
  },
};

Map<String, Object?> agentChatItem(
  String id, {
  String type = 'assistant_message',
  String? turnId = 'turn-1',
  String status = 'completed',
  String text = '',
  String? clientMessageId,
  Map<String, Object?>? normalized,
  Map<String, Object?>? origin,
  String createdAt = _at,
  String? updatedAt,
}) => <String, Object?>{
  'itemId': id,
  'turnId': ?turnId,
  'type': type,
  'status': status,
  'streaming': status == 'inProgress',
  'createdAt': createdAt,
  'updatedAt': updatedAt ?? createdAt,
  'text': text,
  'clientMessageId': ?clientMessageId,
  'normalized': ?normalized,
  'origin': ?origin,
};

Map<String, Object?> agentChatTurn(
  String id, {
  String status = 'completed',
  String startedAt = _at,
  String? completedAt = '2026-10-12T10:00:04Z',
}) => <String, Object?>{
  'turnId': id,
  'status': status,
  'startedAt': startedAt,
  'completedAt': ?completedAt,
};

Map<String, Object?> agentChatSnapshot({
  int cursor = 3,
  List<Map<String, Object?>> items = const <Map<String, Object?>>[],
  List<Map<String, Object?>> turns = const <Map<String, Object?>>[],
  List<Map<String, Object?>> pendingRequests = const <Map<String, Object?>>[],
  List<Map<String, Object?>> queue = const <Map<String, Object?>>[],
  Map<String, Object?>? session,
  bool archived = false,
  Map<String, Object?>? recovery,
  String? historyBefore,
}) => <String, Object?>{
  'chatId': 'chat-1',
  'workspaceId': 'workspace-1',
  'tabId': 'tab-chat',
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'title': 'Fix the build',
  'archived': archived,
  'cursor': cursor,
  'session': session ?? agentChatSession(),
  'turns': turns,
  'items': items,
  'pendingRequests': pendingRequests,
  'queue': queue,
  'recovery': ?recovery,
  'historyBefore': ?historyBefore,
};
