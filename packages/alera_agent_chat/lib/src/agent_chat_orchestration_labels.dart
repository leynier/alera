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
