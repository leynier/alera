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

int compareMobileAgentActivity({
  required MobileWorkspaceAttention leftAttention,
  required DateTime leftFallback,
  required String leftName,
  required MobileWorkspaceAttention rightAttention,
  required DateTime rightFallback,
  required String rightName,
}) {
  final byClass = leftAttention.attentionClass.index.compareTo(
    rightAttention.attentionClass.index,
  );
  if (byClass != 0) return byClass;
  final byTime = (rightAttention.at ?? rightFallback).compareTo(
    leftAttention.at ?? leftFallback,
  );
  if (byTime != 0) return byTime;
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
