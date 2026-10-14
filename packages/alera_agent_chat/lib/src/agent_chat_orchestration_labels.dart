import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_target.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_task.dart';

/// Where a task row sits in Activity: what needs someone, what still runs,
/// and what is done.
enum AgentChatTaskBucket(final String label) {
  attention('Attention'),
  active('Active'),
  history('History');

  static AgentChatTaskBucket of(AgentChatTask task) => task.needsAttention
      ? AgentChatTaskBucket.attention
      : task.status.settled
      ? AgentChatTaskBucket.history
      : AgentChatTaskBucket.active;
}

// Copy both apps show for chat tasks, so a task reads the same on the
// desktop and on a phone.

String agentChatTaskStatusLabel(AgentChatTaskStatus status) => switch (status) {
  AgentChatTaskStatus.preparing => 'Preparing',
  AgentChatTaskStatus.running => 'Running',
  AgentChatTaskStatus.needsInput => 'Needs Input',
  AgentChatTaskStatus.completed => 'Completed',
  AgentChatTaskStatus.failed => 'Failed',
  AgentChatTaskStatus.interrupted => 'Interrupted',
  AgentChatTaskStatus.cancelRequested => 'Cancelling',
  AgentChatTaskStatus.cancelled => 'Cancelled',
};

/// Why a task is in Attention, as row prose.
String? agentChatTaskAttentionLabel(AgentChatTask task) =>
    switch (task.attention) {
      AgentChatTaskAttention.none => null,
      AgentChatTaskAttention.needsInput =>
        task.pendingRequestCount > 1
            ? '${task.pendingRequestCount} requests waiting'
            : 'Waiting for input',
      AgentChatTaskAttention.failed => 'Failed, not reviewed yet',
    };

String agentChatTaskKindLabel(AgentChatTaskKind kind) => switch (kind) {
  AgentChatTaskKind.delegate => 'Delegated Task',
  AgentChatTaskKind.message => 'Message',
};

String agentChatWorkspaceModeLabel(AgentChatWorkspaceMode mode) =>
    switch (mode) {
      AgentChatWorkspaceMode.worktree => 'New Worktree',
      AgentChatWorkspaceMode.shared => 'Project Folder',
    };

String agentChatWorkspaceSetupLabel(AgentChatWorkspaceSetup setup) =>
    switch (setup) {
      AgentChatWorkspaceSetup.inline => 'Before Start',
      AgentChatWorkspaceSetup.deferred => 'In Setup Tab',
    };

/// The target as the detail view names it.
String agentChatTaskTargetLabel(AgentChatTaskTarget? target) =>
    switch (target) {
      AgentChatTaskChatTarget() => 'Existing Chat',
      AgentChatTaskWorkspaceTarget() => 'New Chat',
      AgentChatTaskNewWorkspaceTarget(:final mode) =>
        'New Chat in ${agentChatWorkspaceModeLabel(mode)}',
      null => 'Unknown Target',
    };

String agentChatTaskDeliveryLabel(AgentChatTaskDelivery delivery) =>
    switch (delivery) {
      AgentChatTaskDelivery.pending => 'Not Delivered',
      AgentChatTaskDelivery.notified => 'Parent Notified',
      AgentChatTaskDelivery.acknowledged => 'Acknowledged',
    };

/// Who created a task, from the actor the runtime stamped on it.
String agentChatTaskActorLabel(String? actor) {
  final value = actor ?? '';
  final kind = value.split(':').first;
  return switch (kind) {
    'desktop' => 'Desktop',
    'mobile' => 'Phone',
    'cli' => 'CLI',
    'mcp' => 'MCP Client',
    'agent' => 'Agent',
    'runtime' => 'Alera',
    _ => value.isEmpty ? 'Unknown' : value,
  };
}

/// `just now`, `4m ago`, `2h ago`, `3d ago`, then the date.
String agentChatTaskAgeLabel(DateTime value, DateTime now) {
  final age = now.difference(value);
  if (age < const Duration(minutes: 1)) return 'just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes}m ago';
  if (age < const Duration(days: 1)) return '${age.inHours}h ago';
  if (age < const Duration(days: 7)) return '${age.inDays}d ago';
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// The workspace line of a row: project and workspace names the runtime
/// resolved, else what the app knows, else the ids.
String agentChatTaskPlaceLabel(
  AgentChatTask task, {
  String? projectName,
  String? workspaceName,
}) {
  final project = task.labels.projectName ?? projectName;
  final workspace =
      task.labels.workspaceName ?? workspaceName ?? task.workspaceId;
  final host = task.labels.hostLabel;
  final place = <String>[?project, ?workspace].join(' / ');
  final placed = place.isEmpty ? 'Workspace Pending' : place;
  return host == null ? placed : '$placed · $host';
}

String agentChatOriginHeading(
  AgentChatItemOrigin origin,
) => switch (origin.kind) {
  .orchestrationWake =>
    origin.taskIds.isEmpty
        ? 'Resumed after delegated work finished'
        : 'Resumed after ${origin.taskIds.length} delegated ${origin.taskIds.length == 1 ? 'task' : 'tasks'} finished',
  .chatMessage =>
    origin.taskIds.isNotEmpty ? 'Task' : 'Message from another chat',
  .user => 'Message',
};

bool agentChatOriginStartsExpanded(AgentChatItemOrigin origin) =>
    origin.kind == .chatMessage && origin.taskIds.isNotEmpty;

String agentChatTaskOriginLabel(AgentChatTask task, {String? parentTitle}) {
  if (task.parentChatId != null) {
    final parent =
        parentTitle ?? task.labels.parentChatTitle ?? 'a parent chat';
    return task.kind == .delegate
        ? 'Delegated by $parent'
        : 'Sent by $parent, reply expected';
  }
  if (task.kind == .message) return 'Sent by you, reply expected';
  return switch (task.actor?.split(':').first) {
    'cli' => 'Delegated from CLI',
    'mcp' => 'Delegated from MCP Client',
    _ => 'Delegated by you',
  };
}

/// Builds a delegation brief from canonical plan fields, never raw payloads.
String agentChatPlanTaskBrief(AgentChatItem plan) {
  final explanation = plan.explanation?.trim() ?? '';
  final sections = <String>[
    'Implement the following plan.',
    if (explanation.isNotEmpty) explanation,
    if (plan.text.trim().isNotEmpty) plan.text.trim(),
  ];
  if (plan.planSteps.isNotEmpty) {
    final steps = <String>[
      for (final step in plan.planSteps)
        if (step.step.trim().isNotEmpty) step.step.trim(),
    ];
    sections.add(
      <String>[
        'Steps:',
        for (var index = 0; index < steps.length; index++)
          '${index + 1}. ${steps[index]}',
      ].join('\n'),
    );
  }
  return sections.join('\n\n');
}

String agentChatPlanTaskTitle(AgentChatItem plan) {
  var title = plan.title?.trim() ?? '';
  if (title.isEmpty) {
    for (final line in plan.text.split('\n')) {
      final candidate = line.trim().replaceFirst(RegExp(r'^[#*\-\s]+'), '');
      if (candidate.isNotEmpty) {
        title = candidate;
        break;
      }
    }
  }
  if (title.isEmpty) title = 'Implement Plan';
  final characters = title.runes.take(81).toList();
  return characters.length <= 80
      ? title
      : '${String.fromCharCodes(characters.take(79))}…';
}
