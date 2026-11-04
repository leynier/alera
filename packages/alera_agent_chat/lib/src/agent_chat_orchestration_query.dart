import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_task.dart';
import 'package:alera_agent_chat/src/agent_chat_request.dart';

/// The filters of `chatOrchestration.tasks.list`, and the identity of a
/// watched list, so it compares by value.
class const AgentChatTaskQuery({
  final Set<AgentChatTaskStatus> statuses = const <AgentChatTaskStatus>{},
  final bool? attention,
  final String? parentChatId,
  final String? childChatId,
  final String? rootTaskId,
  final String? projectId,
  final String? workspaceId,
  final int limit = defaultLimit,
}) {
  static const int defaultLimit = 50;

  AgentChatJson toJson({String? cursor}) => <String, Object?>{
    if (statuses.isNotEmpty)
      'statuses': <String>[
        for (final status in AgentChatTaskStatus.values)
          if (statuses.contains(status)) status.wire,
      ],
    'attention': ?attention,
    'parentChatId': ?parentChatId,
    'childChatId': ?childChatId,
    'rootTaskId': ?rootTaskId,
    'projectId': ?projectId,
    'workspaceId': ?workspaceId,
    'limit': limit,
    'cursor': ?cursor,
  };

  /// Whether [change] can alter this list. The event names a task by its
  /// chats and workspace; a field it leaves out is a wildcard, so only a
  /// field that names something else rules the change out.
  bool mayChange(AgentChatTaskChange change) =>
      _compatible(parentChatId, change.parentChatId) &&
      _compatible(childChatId, change.childChatId) &&
      _compatible(workspaceId, change.workspaceId);

  static bool _compatible(String? filter, String? named) =>
      filter == null || named == null || filter == named;

  @override
  bool operator ==(Object other) =>
      other is AgentChatTaskQuery &&
      other.attention == attention &&
      other.parentChatId == parentChatId &&
      other.childChatId == childChatId &&
      other.rootTaskId == rootTaskId &&
      other.projectId == projectId &&
      other.workspaceId == workspaceId &&
      other.limit == limit &&
      other.statuses.length == statuses.length &&
      other.statuses.containsAll(statuses);

  @override
  int get hashCode => Object.hash(
    attention,
    parentChatId,
    childChatId,
    rootTaskId,
    projectId,
    workspaceId,
    limit,
    Object.hashAllUnordered(statuses),
  );
}

/// One page of tasks, newest activity first as the runtime orders them.
class const AgentChatTaskPage({
  required final List<AgentChatTask> tasks,
  final String? nextCursor,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTaskPage(
      tasks: agentChatTasksFromJson(json['tasks']),
      nextCursor: agentChatJsonString(json['nextCursor']),
    );
  }

  static const AgentChatTaskPage empty = AgentChatTaskPage(
    tasks: <AgentChatTask>[],
  );
}

/// Tasks in a JSON list; rows without a task id are skipped.
List<AgentChatTask> agentChatTasksFromJson(Object? value) => <AgentChatTask>[
  for (final task in agentChatJsonList(value))
    if (task is Map &&
        agentChatJsonString(task['taskId'] ?? task['id']) != null)
      AgentChatTask.fromJson(task),
];

/// `chatOrchestrationChanged`: which task changed, by its chats and
/// workspace. A missing field means "may be any".
class const AgentChatTaskChange({
  final String? taskId,
  final String? parentChatId,
  final String? childChatId,
  final String? workspaceId,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTaskChange(
      taskId: agentChatJsonString(json['taskId']),
      parentChatId: agentChatJsonString(json['parentChatId']),
      childChatId: agentChatJsonString(json['childChatId']),
      workspaceId: agentChatJsonString(json['workspaceId']),
    );
  }

  /// A reconnect: anything may have changed while the connection was down.
  static const AgentChatTaskChange any = AgentChatTaskChange();

  bool concerns(String taskId) => this.taskId == null || this.taskId == taskId;
}

/// The answer of a bounded `chatOrchestration.wait`.
class const AgentChatTaskWaitResult({
  required final List<AgentChatTask> tasks,
  required final bool timedOut,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTaskWaitResult(
      tasks: agentChatTasksFromJson(json['tasks']),
      timedOut: agentChatJsonBool(json['timedOut']),
    );
  }
}

/// An open request of a task's child chat, answered like any chat request.
class const AgentChatTaskRequest({
  required final String chatId,
  required final AgentChatRequest request,
  final String? taskId,
  final String? workspaceId,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final chatId = agentChatJsonString(json['chatId']);
    if (chatId == null) {
      throw const FormatException('Chat task request has no chatId.');
    }
    return AgentChatTaskRequest(
      chatId: chatId,
      request: AgentChatRequest.fromJson(json['request']),
      taskId: agentChatJsonString(json['taskId']),
      workspaceId: agentChatJsonString(json['workspaceId']),
    );
  }
}

List<AgentChatTaskRequest> agentChatTaskRequestsFromJson(Object? value) {
  final rows = <AgentChatTaskRequest>[];
  for (final row in agentChatJsonList(agentChatJsonMap(value)['requests'])) {
    try {
      rows.add(AgentChatTaskRequest.fromJson(row));
    } on FormatException {
      // A row the client cannot answer is left for the chat view.
    }
  }
  return rows;
}
