import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// Urgency buckets for the Agent Activity sort. Ordinal order is sort order:
/// agents needing input outrank finished ones, which outrank running ones.
enum AgentAttentionClass { needsYou, done, working, idle }

/// Agent statuses older than this no longer influence the Agent Activity
/// ordering; stale runs fall back to the workspace recency timestamp.
const Duration agentActivityStaleness = Duration(minutes: 30);

class WorkspaceAttention {
  const WorkspaceAttention({required this.attentionClass, this.attentionAt});

  static const WorkspaceAttention idle = WorkspaceAttention(
    attentionClass: AgentAttentionClass.idle,
  );

  final AgentAttentionClass attentionClass;

  /// When the most urgent run entered its current state. Null for idle.
  final DateTime? attentionAt;
}

/// Comparable activity for a workspace that currently has an open terminal.
class AgentActivityRank {
  const AgentActivityRank({
    required this.attentionClass,
    required this.activityAt,
  });

  final AgentAttentionClass attentionClass;
  final DateTime activityAt;
}

/// Classifies a workspace by its live agent runs for the Agent Activity sort.
WorkspaceAttention workspaceAttention({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
  required DateTime now,
}) {
  var best = WorkspaceAttention.idle;
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
