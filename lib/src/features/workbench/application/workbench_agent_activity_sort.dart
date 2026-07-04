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
  if (status.interrupted ?? false) {
    return AgentAttentionClass.needsYou;
  }
  return switch (status.state) {
    AgentStatusState.waiting ||
    AgentStatusState.blocked => AgentAttentionClass.needsYou,
    AgentStatusState.done => AgentAttentionClass.done,
    AgentStatusState.working => AgentAttentionClass.working,
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

/// Comparator for the Agent Activity sort: urgency class ascending, then the
/// attention (or fallback recency) timestamp descending, then name.
int compareByAgentActivity({
  required WorkspaceAttention aAttention,
  required DateTime aFallback,
  required String aName,
  required WorkspaceAttention bAttention,
  required DateTime bFallback,
  required String bName,
}) {
  final byClass = aAttention.attentionClass.index.compareTo(
    bAttention.attentionClass.index,
  );
  if (byClass != 0) {
    return byClass;
  }
  final aAt = aAttention.attentionAt ?? aFallback;
  final bAt = bAttention.attentionAt ?? bFallback;
  final byTime = bAt.compareTo(aAt);
  if (byTime != 0) {
    return byTime;
  }
  return aName.toLowerCase().compareTo(bName.toLowerCase());
}

/// Mutable holder for the workspace order of the last sidebar render. Owned by
/// a keep-alive provider so [buildSidebarRows] can stay pure while the active
/// row keeps its position across rebuilds.
class SidebarOrderMemory {
  List<String> order = const <String>[];
}

/// Re-inserts the active workspace at the index it occupied in the previously
/// rendered order so live status changes never reorder the row the user is
/// interacting with.
List<T> stabilizeActiveEntry<T>({
  required List<T> sorted,
  required String Function(T) idOf,
  required List<String> previousOrder,
  required String? activeId,
}) {
  if (activeId == null) {
    return sorted;
  }
  final currentIndex = sorted.indexWhere((entry) => idOf(entry) == activeId);
  if (currentIndex < 0) {
    return sorted;
  }
  final previousIndex = previousOrder.indexOf(activeId);
  if (previousIndex < 0 || previousIndex == currentIndex) {
    return sorted;
  }
  final result = List<T>.from(sorted);
  final entry = result.removeAt(currentIndex);
  result.insert(
    previousIndex >= result.length ? result.length : previousIndex,
    entry,
  );
  return result;
}
