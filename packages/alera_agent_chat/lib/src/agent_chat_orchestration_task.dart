import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_target.dart';

/// Where a task is. It settles with the child's turn started for it, never
/// with the acknowledgement of the request that created it.
enum AgentChatTaskStatus(final String wire) {
  preparing('preparing'),
  running('running'),
  needsInput('needs_input'),
  completed('completed'),
  failed('failed'),
  interrupted('interrupted'),
  cancelRequested('cancel_requested'),
  cancelled('cancelled');

  /// An unknown status reads as running, so a newer runtime's state never
  /// hides an unfinished task in History.
  static AgentChatTaskStatus fromJson(Object? value) =>
      tryParse(value) ?? AgentChatTaskStatus.running;

  static AgentChatTaskStatus? tryParse(Object? value) {
    final token = agentChatWireToken(value);
    for (final status in values) {
      if (agentChatWireToken(status.wire) == token) return status;
    }
    return null;
  }

  bool get settled => switch (this) {
    AgentChatTaskStatus.completed ||
    AgentChatTaskStatus.failed ||
    AgentChatTaskStatus.interrupted ||
    AgentChatTaskStatus.cancelled => true,
    _ => false,
  };

  /// Whether cancelling still has something to stop.
  bool get cancellable => switch (this) {
    AgentChatTaskStatus.preparing ||
    AgentChatTaskStatus.running ||
    AgentChatTaskStatus.needsInput => true,
    _ => false,
  };
}

/// A delegation, or a message that expects a reply.
enum AgentChatTaskKind(final String wire) {
  delegate('delegate'),
  message('message');

  static AgentChatTaskKind fromJson(Object? value) =>
      agentChatWireToken(value) == 'message'
      ? AgentChatTaskKind.message
      : AgentChatTaskKind.delegate;
}

/// Whether the parent chat is woken when the task settles.
enum AgentChatTaskNotify(final String wire) {
  always('always'),
  settledOnly('settled_only'),
  never('never');

  static AgentChatTaskNotify? tryParse(Object? value) {
    final token = agentChatWireToken(value);
    for (final notify in values) {
      if (agentChatWireToken(notify.wire) == token) return notify;
    }
    return null;
  }
}

/// How far a settled result travelled towards whoever owns the task.
enum AgentChatTaskDelivery(final String wire) {
  pending('pending'),
  notified('notified'),
  acknowledged('acknowledged');

  static AgentChatTaskDelivery fromJson(Object? value) =>
      switch (agentChatWireToken(value)) {
        'notified' => AgentChatTaskDelivery.notified,
        'acknowledged' => AgentChatTaskDelivery.acknowledged,
        _ => AgentChatTaskDelivery.pending,
      };
}

/// Why a task needs a person or its parent.
enum AgentChatTaskAttention { none, needsInput, failed }

/// The bounded final assistant text of the turn that settled the task. The
/// runtime never includes reasoning or tool payloads.
class const AgentChatTaskResult({
  required final String text,
  final bool truncated = false,
  final String? turnId,
}) {
  factory fromJson(Object? value) {
    if (value is String) return AgentChatTaskResult(text: value);
    final json = agentChatJsonMap(value);
    return AgentChatTaskResult(
      text: agentChatJsonText(json['text']),
      truncated: agentChatJsonBool(json['truncated']),
      turnId: agentChatJsonString(json['turnId']),
    );
  }
}

class const AgentChatTaskFailure({
  required final String message,
  final String? code,
}) {
  factory fromJson(Object? value) {
    if (value is String) return AgentChatTaskFailure(message: value);
    final json = agentChatJsonMap(value);
    return AgentChatTaskFailure(
      message: agentChatJsonText(json['message']),
      code: agentChatJsonString(json['code']),
    );
  }
}

/// Display names the runtime resolved, including for chats and workspaces on
/// other hosts that this client does not list itself.
class const AgentChatTaskLabels({
  final String? parentChatTitle,
  final String? childChatTitle,
  final String? projectName,
  final String? workspaceName,
  final String? hostLabel,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatTaskLabels(
      parentChatTitle: agentChatJsonString(json['parentChatTitle']),
      childChatTitle: agentChatJsonString(json['childChatTitle']),
      projectName: agentChatJsonString(json['projectName']),
      workspaceName: agentChatJsonString(json['workspaceName']),
      hostLabel: agentChatJsonString(json['hostLabel']),
    );
  }
}

/// One task as `chatOrchestration.*` projects it. [id] is the app-owned task
/// id, distinct from [childChatId]: a follow-up in the same child chat is a
/// new task.
class const AgentChatTask({
  required final String id,
  required final AgentChatTaskStatus status,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final AgentChatTaskKind kind = AgentChatTaskKind.delegate,
  final String? title,
  final String? role,
  final String? brief,
  final String? parentTaskId,
  final String? rootTaskId,
  final int depth = 0,
  final String? parentChatId,
  final String? childChatId,
  final AgentChatTaskTarget? target,
  final String? projectId,
  final String? workspaceId,
  final String? hostId,
  final String? provider,
  final String? providerInstanceId,
  final String? model,
  final AgentChatRuntimeMode? runtimeMode,
  final AgentChatTaskNotify? notify,
  final AgentChatTaskAttention attention = AgentChatTaskAttention.none,
  final int pendingRequestCount = 0,
  final AgentChatTaskDelivery delivery = AgentChatTaskDelivery.pending,
  final AgentChatTaskResult? result,
  final AgentChatTaskFailure? failure,
  final String? actor,
  final DateTime? completedAt,
  final AgentChatTaskLabels labels = const AgentChatTaskLabels(),
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['taskId'] ?? json['id']);
    if (id == null) {
      throw const FormatException('Chat task has no taskId.');
    }
    final status = AgentChatTaskStatus.fromJson(json['status']);
    final delivery = AgentChatTaskDelivery.fromJson(
      json['resultDelivery'] ?? json['delivery'],
    );
    final target = AgentChatTaskTarget.fromJson(json['target']);
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final createdAt = agentChatJsonDate(json['createdAt']) ?? epoch;
    return AgentChatTask(
      id: id,
      status: status,
      createdAt: createdAt,
      updatedAt: agentChatJsonDate(json['updatedAt']) ?? createdAt,
      kind: AgentChatTaskKind.fromJson(json['kind']),
      title: agentChatJsonString(json['title']),
      role: agentChatJsonString(json['role']),
      brief: agentChatJsonString(json['brief']),
      parentTaskId: agentChatJsonString(json['parentTaskId']),
      rootTaskId: agentChatJsonString(json['rootTaskId']),
      depth: agentChatJsonInt(json['depth']) ?? 0,
      parentChatId: agentChatJsonString(json['parentChatId']),
      childChatId: agentChatJsonString(json['childChatId']),
      target: target,
      projectId: agentChatJsonString(json['projectId']),
      workspaceId:
          agentChatJsonString(json['workspaceId']) ??
          switch (target) {
            AgentChatTaskWorkspaceTarget(:final workspaceId) => workspaceId,
            _ => null,
          },
      hostId: agentChatJsonString(json['hostId']),
      provider: agentChatJsonString(json['provider']),
      providerInstanceId: agentChatJsonString(json['providerInstanceId']),
      model: agentChatJsonString(json['model']),
      runtimeMode: AgentChatRuntimeMode.tryParse(json['runtimeMode']),
      notify: AgentChatTaskNotify.tryParse(json['notify']),
      attention: _attention(json, status, delivery),
      pendingRequestCount: agentChatJsonInt(json['pendingRequestCount']) ?? 0,
      delivery: delivery,
      result: json['result'] == null
          ? null
          : AgentChatTaskResult.fromJson(json['result']),
      failure: json['error'] == null
          ? null
          : AgentChatTaskFailure.fromJson(json['error']),
      actor: agentChatJsonString(json['actor']),
      completedAt: agentChatJsonDate(json['completedAt']),
      labels: AgentChatTaskLabels.fromJson(json['labels']),
    );
  }

  /// No chat waits for this result: a person, the CLI or an MCP client
  /// created it. Only such tasks are acknowledged when a person reads them.
  bool get ownedByPerson => parentChatId == null;

  bool get needsAttention => attention != AgentChatTaskAttention.none;

  /// The list name: the title, else the first line of the brief.
  String get displayTitle {
    final title = this.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final line = brief
        ?.split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (line == null || line.isEmpty) return 'Task $id';
    return line.length > 120 ? '${line.substring(0, 119)}…' : line;
  }
}

/// The runtime decides attention; a payload without the flag falls back to
/// the same rule: open requests, or a failure nobody acknowledged yet.
AgentChatTaskAttention _attention(
  AgentChatJson json,
  AgentChatTaskStatus status,
  AgentChatTaskDelivery delivery,
) {
  final kind = AgentChatTaskStatus.tryParse(json['attentionKind']);
  final flag = json['attention'];
  final needed = flag is bool
      ? flag
      : status == AgentChatTaskStatus.needsInput ||
            (status == AgentChatTaskStatus.failed &&
                delivery != AgentChatTaskDelivery.acknowledged);
  if (!needed) return AgentChatTaskAttention.none;
  return switch (kind ?? status) {
    AgentChatTaskStatus.failed => AgentChatTaskAttention.failed,
    _ => AgentChatTaskAttention.needsInput,
  };
}
