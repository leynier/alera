import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';

enum MobileAgentAttentionClass { needsYou, done, working, idle }

const Duration mobileAgentActivityStaleness = Duration(minutes: 30);

class MobileWorkspaceAttention {
  const MobileWorkspaceAttention({required this.attentionClass, this.at});

  static const idle = MobileWorkspaceAttention(
    attentionClass: MobileAgentAttentionClass.idle,
  );

  final MobileAgentAttentionClass attentionClass;
  final DateTime? at;
}

class MobileAgentActivityRank {
  const MobileAgentActivityRank({
    required this.attentionClass,
    required this.activityAt,
  });

  final MobileAgentAttentionClass attentionClass;
  final DateTime activityAt;
}

MobileWorkspaceAttention mobileWorkspaceAttention({
  required String workspaceId,
  required Iterable<AgentPresenceSummary> statuses,
  required DateTime now,
}) {
  var best = MobileWorkspaceAttention.idle;
  for (final status in statuses) {
    if (status.workspaceId != workspaceId) continue;
    final startedAt = status.stateStartedAt;
    if (startedAt == null ||
        now.difference(startedAt) > mobileAgentActivityStaleness) {
      continue;
    }
    final candidate = MobileWorkspaceAttention(
      attentionClass: switch (status.state) {
        'waiting' || 'blocked' => MobileAgentAttentionClass.needsYou,
        'done' => MobileAgentAttentionClass.done,
        'working' => MobileAgentAttentionClass.working,
        _ => MobileAgentAttentionClass.idle,
      },
      at: startedAt,
    );
    if (_moreUrgent(candidate, best)) best = candidate;
  }
  return best;
}

MobileAgentActivityRank mobileAgentActivityRank({
  required MobileWorkspaceAttention attention,
  required DateTime fallback,
}) {
  return MobileAgentActivityRank(
    attentionClass: attention.attentionClass,
    activityAt: attention.at ?? fallback,
  );
}

int compareMobileAgentActivityRanks(
  MobileAgentActivityRank left,
  MobileAgentActivityRank right,
) {
  final byClass = left.attentionClass.index.compareTo(
    right.attentionClass.index,
  );
  if (byClass != 0) return byClass;
  return right.activityAt.compareTo(left.activityAt);
}

MobileAgentActivityRank? bestMobileAgentActivityRank(
  MobileAgentActivityRank? current,
  MobileAgentActivityRank? candidate,
) {
  if (current == null) return candidate;
  if (candidate == null) return current;
  return compareMobileAgentActivityRanks(candidate, current) < 0
      ? candidate
      : current;
}

Map<String, MobileAgentActivityRank?> aggregateMobileAgentActivityBySubtree({
  required Iterable<({String id, String? parentId})> workspaces,
  required Map<String, MobileAgentActivityRank?> directActivityByWorkspaceId,
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

  final aggregateById = <String, MobileAgentActivityRank?>{};
  final visiting = <String>{};

  MobileAgentActivityRank? visit(String workspaceId) {
    final cached = aggregateById[workspaceId];
    if (cached != null || aggregateById.containsKey(workspaceId)) {
      return cached;
    }
    if (!visiting.add(workspaceId)) {
      return directActivityByWorkspaceId[workspaceId];
    }
    var best = directActivityByWorkspaceId[workspaceId];
    for (final childId in childrenByParentId[workspaceId] ?? const <String>[]) {
      best = bestMobileAgentActivityRank(best, visit(childId));
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

int compareMobileAgentActivity({
  required MobileAgentActivityRank? leftActivity,
  required String leftName,
  required MobileAgentActivityRank? rightActivity,
  required String rightName,
}) {
  if (leftActivity == null || rightActivity == null) {
    if (leftActivity != null) return -1;
    if (rightActivity != null) return 1;
    return leftName.toLowerCase().compareTo(rightName.toLowerCase());
  }
  final byActivity = compareMobileAgentActivityRanks(
    leftActivity,
    rightActivity,
  );
  if (byActivity != 0) return byActivity;
  return leftName.toLowerCase().compareTo(rightName.toLowerCase());
}

bool _moreUrgent(
  MobileWorkspaceAttention candidate,
  MobileWorkspaceAttention current,
) {
  if (candidate.attentionClass != current.attentionClass) {
    return candidate.attentionClass.index < current.attentionClass.index;
  }
  final candidateAt = candidate.at;
  final currentAt = current.at;
  if (candidateAt == null || currentAt == null) {
    return currentAt == null && candidateAt != null;
  }
  return candidateAt.isAfter(currentAt);
}
