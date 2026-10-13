import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';

/// A task as the runtime projects it, with every field a test may vary.
Map<String, Object?> chatTaskJson({
  required String taskId,
  String status = 'running',
  String title = 'Port the parser',
  String? parentChatId = 'chat-parent',
  String? childChatId = 'chat-child',
  String? workspaceId = 'ws-1',
  String? projectId = 'project-1',
  bool? attention,
  String resultDelivery = 'pending',
  int pendingRequestCount = 0,
  Map<String, Object?>? result,
  String updatedAt = '2026-08-30T11:00:00Z',
}) => <String, Object?>{
  'taskId': taskId,
  'kind': 'delegate',
  'status': status,
  'title': title,
  'brief': 'Do $title and report back.',
  'rootTaskId': taskId,
  'depth': 0,
  'parentChatId': ?parentChatId,
  'childChatId': ?childChatId,
  'workspaceId': ?workspaceId,
  'projectId': ?projectId,
  'target': <String, Object?>{
    'workspace': <String, Object?>{'workspaceId': workspaceId ?? 'ws-1'},
  },
  'provider': 'codex',
  'providerInstanceId': 'codex',
  'model': 'gpt-5',
  'notify': 'always',
  'attention':
      attention ??
      (status == 'needs_input' ||
          (status == 'failed' && resultDelivery != 'acknowledged')),
  'resultDelivery': resultDelivery,
  'pendingRequestCount': pendingRequestCount,
  'result': ?result,
  'actor': parentChatId == null ? 'desktop' : 'agent:$parentChatId',
  'createdAt': '2026-08-30T10:00:00Z',
  'updatedAt': updatedAt,
};

/// The runtime as both apps' repositories see it: `agentChat.*` and
/// `chatOrchestration.*` answered from memory, with every request logged.
final class FakeChatTaskTransport implements AgentChatTransport {
  FakeChatTaskTransport({this.orchestration = true});

  bool orchestration;
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];
  final Map<String, Map<String, Object?>> tasks =
      <String, Map<String, Object?>>{};
  List<Map<String, Object?>> pendingRequests = <Map<String, Object?>>[];
  List<Map<String, Object?>> chats = <Map<String, Object?>>[];
  List<Map<String, Object?>> providers = <Map<String, Object?>>[
    <String, Object?>{
      'providerInstanceId': 'codex',
      'provider': 'codex',
      'label': 'Codex',
      'models': <Object?>[
        <String, Object?>{'id': 'gpt-5', 'label': 'GPT-5', 'isDefault': true},
      ],
      'runtimeModes': <String>['approval-required', 'full-access'],
      'orchestration': <String, Object?>{'supported': true},
    },
  ];
  int _next = 1;
  final StreamController<AgentChatTransportEvent> _events =
      StreamController<AgentChatTransportEvent>.broadcast(sync: true);

  @override
  Stream<AgentChatTransportEvent> get events => _events.stream;

  @override
  Future<bool> supportsCapability(String capability) async =>
      capability == AgentChatWire.capability ||
      (orchestration && capability == AgentChatOrchestrationWire.capability);

  Iterable<Map<String, Object?>> sent(String verb) => requests
      .where((request) => request.$1 == verb)
      .map((request) => request.$2);

  /// Stores [task] and announces it the way the runtime does.
  void put(Map<String, Object?> task) {
    tasks[task['taskId']! as String] = task;
    changed(task);
  }

  void changed(Map<String, Object?> task) => _events.add(
    AgentChatTransportEvent(AgentChatOrchestrationWire.changedEvent, {
      'taskId': task['taskId'],
      'parentChatId': ?task['parentChatId'],
      'childChatId': ?task['childChatId'],
      'workspaceId': ?task['workspaceId'],
    }),
  );

  void dispose() => unawaited(_events.close());

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload));
    return switch (type) {
      AgentChatOrchestrationWire.tasksList => _list(payload),
      AgentChatOrchestrationWire.task => _read(payload),
      AgentChatOrchestrationWire.cancel => _cancel(payload),
      AgentChatOrchestrationWire.delegate => _delegate(payload),
      AgentChatOrchestrationWire.send => _send(payload),
      AgentChatOrchestrationWire.capabilities => <String, Object?>{
        'maxWaitSeconds': 50,
        'providers': providers,
      },
      AgentChatOrchestrationWire.requests => <String, Object?>{
        'requests': pendingRequests,
      },
      AgentChatOrchestrationWire.respond => <String, Object?>{'resolved': true},
      AgentChatOrchestrationWire.wait => <String, Object?>{
        'tasks': <Object?>[
          for (final id in payload['taskIds']! as List<Object?>) tasks[id],
        ],
        'timedOut': true,
      },
      AgentChatOrchestrationWire.list => <String, Object?>{'chats': chats},
      AgentChatOrchestrationWire.read => <String, Object?>{
        'chat': chats.firstWhere((chat) => chat['chatId'] == payload['chatId']),
        'messages': const <Object?>[],
        'plans': const <Object?>[],
        'truncated': false,
      },
      AgentChatWire.providers => <String, Object?>{'providers': providers},
      AgentChatWire.list => <String, Object?>{'chats': chats},
      AgentChatWire.reopen => <String, Object?>{
        'chatId': payload['chatId'],
        'tabId': 'tab-reopened',
        'snapshot': <String, Object?>{
          'chatId': payload['chatId'],
          'workspaceId': payload['workspaceId'],
        },
      },
      _ => throw AgentChatRequestException(message: 'Unexpected $type'),
    };
  }

  Map<String, Object?> _list(Map<String, Object?> payload) {
    final statuses = (payload['statuses'] as List<Object?>?)?.toSet();
    final rows =
        <Map<String, Object?>>[
          for (final task in tasks.values)
            if ((payload['attention'] != true || task['attention'] == true) &&
                (statuses == null || statuses.contains(task['status'])) &&
                _matches(payload, task, 'parentChatId') &&
                _matches(payload, task, 'workspaceId') &&
                _matches(payload, task, 'projectId'))
              task,
        ]..sort(
          (a, b) =>
              (b['updatedAt']! as String).compareTo(a['updatedAt']! as String),
        );
    final limit = payload['limit'] as int? ?? 50;
    return <String, Object?>{
      'tasks': rows.take(limit).toList(),
      if (rows.length > limit) 'nextCursor': 'more',
    };
  }

  static bool _matches(
    Map<String, Object?> payload,
    Map<String, Object?> task,
    String key,
  ) => payload[key] == null || payload[key] == task[key];

  Map<String, Object?> _read(Map<String, Object?> payload) {
    final id = payload['taskId']! as String;
    final task = tasks[id];
    if (task == null) {
      throw const AgentChatRequestException(
        message: 'No such task.',
        code: 'task_not_found',
      );
    }
    if (payload['acknowledge'] == true) {
      put(<String, Object?>{
        ...task,
        'resultDelivery': 'acknowledged',
        'attention': task['status'] == 'needs_input',
      });
    }
    return <String, Object?>{'task': tasks[id]};
  }

  Map<String, Object?> _cancel(Map<String, Object?> payload) {
    final id = payload['taskId']! as String;
    put(<String, Object?>{...tasks[id]!, 'status': 'cancel_requested'});
    return <String, Object?>{
      'task': tasks[id],
      'cancelledTaskIds': <String>[id],
    };
  }

  Map<String, Object?> _delegate(Map<String, Object?> payload) {
    final id = 'task-new-${_next++}';
    final target = payload['target']! as Map<String, Object?>;
    final workspace = target['workspace'] as Map<String, Object?>?;
    put(<String, Object?>{
      ...chatTaskJson(
        taskId: id,
        status: 'preparing',
        title: payload['title'] as String? ?? 'Delegated',
        parentChatId: null,
        childChatId: null,
        workspaceId: workspace?['workspaceId'] as String?,
        updatedAt: '2026-08-30T12:00:00Z',
      ),
      'target': target,
    });
    return <String, Object?>{
      'taskId': id,
      'status': 'preparing',
      'task': tasks[id],
    };
  }

  Map<String, Object?> _send(Map<String, Object?> payload) {
    final id = 'task-reply-${_next++}';
    put(
      chatTaskJson(
        taskId: id,
        title: 'Follow-up',
        parentChatId: null,
        childChatId: payload['chatId']! as String,
        updatedAt: '2026-08-30T12:30:00Z',
      ),
    );
    return <String, Object?>{
      'chatId': payload['chatId'],
      'delivery': 'started',
      'taskId': id,
    };
  }
}
