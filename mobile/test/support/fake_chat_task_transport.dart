import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';

Map<String, Object?> chatTaskJson({
  required String taskId,
  String status = 'running',
  String title = 'Port the parser',
  String? parentChatId = 'chat-parent',
  String? childChatId = 'chat-child',
  String workspaceId = 'ws-1',
  String resultDelivery = 'pending',
  String updatedAt = '2026-08-30T11:00:00Z',
}) => <String, Object?>{
  'taskId': taskId,
  'kind': 'delegate',
  'status': status,
  'title': title,
  'brief': 'Do $title and report back.',
  'rootTaskId': taskId,
  'parentChatId': ?parentChatId,
  'childChatId': ?childChatId,
  'workspaceId': workspaceId,
  'projectId': 'project-1',
  'target': <String, Object?>{
    'workspace': <String, Object?>{'workspaceId': workspaceId},
  },
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'attention':
      status == 'needs_input' ||
      (status == 'failed' && resultDelivery != 'acknowledged'),
  'resultDelivery': resultDelivery,
  'actor': parentChatId == null ? 'mobile:phone' : 'agent:$parentChatId',
  'createdAt': '2026-08-30T10:00:00Z',
  'updatedAt': updatedAt,
};

/// The paired runtime's `agentChat.*` and `chatOrchestration.*` verbs,
/// answered from memory with every request logged.
final class FakeChatTaskTransport implements AgentChatTransport {
  FakeChatTaskTransport({this.orchestration = true});

  bool orchestration;
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];
  final Map<String, Map<String, Object?>> tasks =
      <String, Map<String, Object?>>{};
  List<Map<String, Object?>> chats = <Map<String, Object?>>[];

  /// Open child requests `chatOrchestration.requests` answers with; a
  /// response removes the one it answers.
  final List<Map<String, Object?>> pendingRequests = <Map<String, Object?>>[];
  final StreamController<AgentChatTransportEvent> _events =
      StreamController<AgentChatTransportEvent>.broadcast(sync: true);
  int _next = 1;

  static const List<Map<String, Object?>> providers = <Map<String, Object?>>[
    <String, Object?>{
      'providerInstanceId': 'codex',
      'provider': 'codex',
      'label': 'Codex',
      'models': <Object?>[
        <String, Object?>{'id': 'gpt-5', 'label': 'GPT-5', 'isDefault': true},
      ],
    },
  ];

  @override
  Stream<AgentChatTransportEvent> get events => _events.stream;

  @override
  Future<bool> supportsCapability(String capability) async =>
      capability == AgentChatWire.capability ||
      (orchestration && capability == AgentChatOrchestrationWire.capability);

  Iterable<Map<String, Object?>> sent(String verb) => requests
      .where((request) => request.$1 == verb)
      .map((request) => request.$2);

  void put(Map<String, Object?> task) {
    tasks[task['taskId']! as String] = task;
    _events.add(
      AgentChatTransportEvent(AgentChatOrchestrationWire.changedEvent, {
        'taskId': task['taskId'],
      }),
    );
  }

  void dispose() => unawaited(_events.close());

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload));
    switch (type) {
      case AgentChatOrchestrationWire.tasksList:
        final statuses = (payload['statuses'] as List<Object?>?)?.toSet();
        return <String, Object?>{
          'tasks': <Object?>[
            for (final task in tasks.values)
              if ((payload['attention'] != true || task['attention'] == true) &&
                  (statuses == null || statuses.contains(task['status'])) &&
                  (payload['parentChatId'] == null ||
                      payload['parentChatId'] == task['parentChatId']))
                task,
          ],
        };
      case AgentChatOrchestrationWire.task:
        final id = payload['taskId']! as String;
        if (payload['acknowledge'] == true) {
          put(<String, Object?>{
            ...tasks[id]!,
            'resultDelivery': 'acknowledged',
            'attention': false,
          });
        }
        return <String, Object?>{'task': tasks[id]};
      case AgentChatOrchestrationWire.cancel:
        final id = payload['taskId']! as String;
        put(<String, Object?>{...tasks[id]!, 'status': 'cancel_requested'});
        return <String, Object?>{
          'task': tasks[id],
          'cancelledTaskIds': <String>[id],
        };
      case AgentChatOrchestrationWire.delegate:
        final id = 'task-new-${_next++}';
        put(<String, Object?>{
          ...chatTaskJson(
            taskId: id,
            status: 'preparing',
            title: 'Delegated',
            parentChatId: null,
            childChatId: null,
          ),
          'target': payload['target'],
        });
        return <String, Object?>{
          'taskId': id,
          'status': 'preparing',
          'task': tasks[id],
        };
      case AgentChatOrchestrationWire.capabilities:
        return <String, Object?>{'maxWaitSeconds': 50, 'providers': providers};
      case AgentChatOrchestrationWire.requests:
        return <String, Object?>{
          'requests': <Object?>[
            for (final request in pendingRequests)
              if (payload['taskId'] == null ||
                  payload['taskId'] == request['taskId'])
                request,
          ],
        };
      case AgentChatOrchestrationWire.respond:
        pendingRequests.removeWhere(
          (request) =>
              (request['request']! as Map<String, Object?>)['requestId'] ==
              (payload['runtimeRequestId'] ?? payload['requestId']),
        );
        return const <String, Object?>{};
      case AgentChatOrchestrationWire.send:
        final id = 'task-sent-${_next++}';
        if (payload['expectReply'] == true) {
          put(<String, Object?>{
            ...chatTaskJson(
              taskId: id,
              title: 'Reply',
              parentChatId: payload['parentChatId'] as String?,
              childChatId: payload['chatId'] as String?,
            ),
            'kind': 'message',
          });
        }
        return <String, Object?>{
          'chatId': payload['chatId'],
          'delivery': 'started',
          if (payload['expectReply'] == true) 'taskId': id,
        };
      case AgentChatOrchestrationWire.list:
        return <String, Object?>{'chats': chats};
      case AgentChatOrchestrationWire.read:
        return <String, Object?>{
          'chat': chats.firstWhere(
            (chat) => chat['chatId'] == payload['chatId'],
          ),
        };
      case AgentChatWire.providers:
        return <String, Object?>{'providers': providers};
      default:
        throw AgentChatRequestException(message: 'Unexpected $type');
    }
  }
}
