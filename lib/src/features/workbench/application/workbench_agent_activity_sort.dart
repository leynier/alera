import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// Urgency buckets for the Agent Activity sort. Ordinal order is sort order:
/// agents needing input outrank finished ones, which outrank running ones.
enum AgentAttentionClass { needsYou, done, working, idle }

/// Agent statuses older than this no longer influence the Agent Activity
/// ordering; stale runs fall back to the workspace recency timestamp.
const Duration agentActivityStaleness = Duration(minutes: 30);

class const WorkspaceAttention({
  required final AgentAttentionClass attentionClass,
  this.attentionAt,
}) {
  static const WorkspaceAttention idle = WorkspaceAttention(
    attentionClass: .idle,
  );

  /// When the most urgent run entered its current state. Null for idle.
  final DateTime? attentionAt;
}

/// Comparable activity for a workspace that currently has an open terminal.
class const AgentActivityRank({
  required final AgentAttentionClass attentionClass,
  required final DateTime activityAt,
});

/// Classifies a workspace by its live agent runs, and its agent chats when
/// [chats] is given, for the Agent Activity sort.
WorkspaceAttention workspaceAttention({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
  required DateTime now,
  ChatWorkspaceAttention? chats,
}) {
  var best = chats == null ? WorkspaceAttention.idle : _chatAttention(chats);
  final runs = visibleWorkspaceAgentRuns(
    tabs: tabs,
    agentStatuses: agentStatuses,
  );
  for (final run in runs) {
    final status = run.status;
    if (now.difference(status.updatedAt) > agentActivityStaleness) {
      continue;
    }
    final candidate = WorkspaceAttention(
      attentionClass: _classify(status),
      attentionAt: status.stateStartedAt,
    );
    if (_moreUrgent(candidate, best)) {
      best = candidate;
    }
  }
  return best;
}

// A chat's attention comes from the runtime, so it never goes stale the way
// an old terminal hook does.
WorkspaceAttention _chatAttention(
  ChatWorkspaceAttention chats,
) => switch (chats.level) {
  ChatAttentionLevel.needsInput || ChatAttentionLevel.failed =>
    WorkspaceAttention(attentionClass: .needsYou, attentionAt: chats.latestAt),
  ChatAttentionLevel.unread => WorkspaceAttention(
    attentionClass: .done,
    attentionAt: chats.latestAt,
  ),
  ChatAttentionLevel.working || ChatAttentionLevel.waitingOnTasks =>
    WorkspaceAttention(attentionClass: .working, attentionAt: chats.latestAt),
  ChatAttentionLevel.idle => WorkspaceAttention.idle,
};

AgentAttentionClass _classify(AgentStatusEntry status) {
  if (agentStatusNeedsYou(status)) {
    return AgentAttentionClass.needsYou;
  }
  return switch (status.state) {
    AgentStatusState.done => AgentAttentionClass.done,
    AgentStatusState.working => AgentAttentionClass.working,
    AgentStatusState.waiting ||
    AgentStatusState.blocked => AgentAttentionClass.needsYou,
  };
}

bool _moreUrgent(WorkspaceAttention a, WorkspaceAttention b) {
  if (a.attentionClass != b.attentionClass) {
    return a.attentionClass.index < b.attentionClass.index;
  }
  final aAt = a.attentionAt;
  final bAt = b.attentionAt;
  if (aAt == null || bAt == null) {
    return bAt == null && aAt != null;
  }
  return aAt.isAfter(bAt);
}

AgentActivityRank agentActivityRank({
  required WorkspaceAttention attention,
  required DateTime fallback,
}) {
  return AgentActivityRank(
    attentionClass: attention.attentionClass,
    activityAt: attention.attentionAt ?? fallback,
  );
}

int compareAgentActivityRanks(AgentActivityRank a, AgentActivityRank b) {
  final byClass = a.attentionClass.index.compareTo(b.attentionClass.index);
  if (byClass != 0) {
    return byClass;
  }
  return b.activityAt.compareTo(a.activityAt);
}

AgentActivityRank? bestAgentActivityRank(
  AgentActivityRank? current,
  AgentActivityRank? candidate,
) {
  if (current == null) {
    return candidate;
  }
  if (candidate == null) {
    return current;
  }
  return compareAgentActivityRanks(candidate, current) < 0
      ? candidate
      : current;
}

/// Returns each workspace's best activity across itself and its visible
/// descendants. A cycle edge contributes the node's direct activity without
/// recursing again.
Map<String, AgentActivityRank?> aggregateAgentActivityBySubtree({
  required Iterable<({String id, String? parentId})> workspaces,
  required Map<String, AgentActivityRank?> directActivityByWorkspaceId,
}) {
  final entries = workspaces.toList(growable: false);
  final ids = <String>{for (final entry in entries) entry.id};
  final childrenByParentId = <String, List<String>>{};
  for (final entry in entries) {
    final parentId = entry.parentId;
    if (parentId == null || parentId == entry.id || !ids.contains(parentId)) {
      continue;
    }
    childrenByParentId.putIfAbsent(parentId, () => <String>[]).add(entry.id);
  }

  final aggregateById = <String, AgentActivityRank?>{};
  final visiting = <String>{};

  AgentActivityRank? visit(String workspaceId) {
    final cached = aggregateById[workspaceId];
    if (cached != null || aggregateById.containsKey(workspaceId)) {
      return cached;
    }
    if (!visiting.add(workspaceId)) {
      return directActivityByWorkspaceId[workspaceId];
    }
    var best = directActivityByWorkspaceId[workspaceId];
    for (final childId in childrenByParentId[workspaceId] ?? const <String>[]) {
      best = bestAgentActivityRank(best, visit(childId));
    }
    visiting.remove(workspaceId);
    aggregateById[workspaceId] = best;
    return best;
  }

  for (final entry in entries) {
    visit(entry.id);
  }
  return aggregateById;
}

/// Comparator for the Agent Activity sort. Entries with terminal activity
/// rank first by urgency and time; entries without terminals sort by name.
int compareByAgentActivity({
  required AgentActivityRank? aActivity,
  required String aName,
  required AgentActivityRank? bActivity,
  required String bName,
}) {
  if (aActivity == null || bActivity == null) {
    if (aActivity != null) {
      return -1;
    }
    if (bActivity != null) {
      return 1;
    }
    return aName.toLowerCase().compareTo(bName.toLowerCase());
  }
  final byActivity = compareAgentActivityRanks(aActivity, bActivity);
  if (byActivity != 0) {
    return byActivity;
  }
  return aName.toLowerCase().compareTo(bName.toLowerCase());
}

/// Orders runs the way the Agent Activity sort orders workspaces: agents that
/// need the user first, then finished, then working, then stale ones, each
/// most recent first. Ties keep the incoming order.
List<WorkspaceAgentRun> sortWorkspaceAgentRunsByActivity(
  List<WorkspaceAgentRun> runs, {
  required DateTime now,
}) {
  final ranked = [
    for (final (index, run) in runs.indexed)
      (index: index, run: run, rank: _runActivityRank(run.status, now)),
  ];
  ranked.sort((a, b) {
    final byRank = compareAgentActivityRanks(a.rank, b.rank);
    return byRank != 0 ? byRank : a.index.compareTo(b.index);
  });
  return [for (final entry in ranked) entry.run];
}

AgentActivityRank _runActivityRank(AgentStatusEntry status, DateTime now) {
  final stale = now.difference(status.updatedAt) > agentActivityStaleness;
  return AgentActivityRank(
    attentionClass: stale ? AgentAttentionClass.idle : _classify(status),
    activityAt: stale ? status.updatedAt : status.stateStartedAt,
  );
}
