enum ChunkingMode { smooth, catchUp }

class QueueSnapshot {
  const QueueSnapshot({required this.queuedLines, required this.oldestAge});

  final int queuedLines;
  final Duration? oldestAge;
}

class DrainPlan {
  const DrainPlan.single() : isBatch = false, maxLines = 1;

  const DrainPlan.batch(this.maxLines) : isBatch = true;

  final bool isBatch;
  final int maxLines;
}

class ChunkingDecision {
  const ChunkingDecision({
    required this.mode,
    required this.enteredCatchUp,
    required this.drainPlan,
  });

  final ChunkingMode mode;
  final bool enteredCatchUp;
  final DrainPlan drainPlan;
}

class AdaptiveChunkingPolicyState {
  const AdaptiveChunkingPolicyState({
    this.mode = ChunkingMode.smooth,
    this.belowExitThresholdSince,
    this.lastCatchUpExitAt,
  });

  final ChunkingMode mode;
  final DateTime? belowExitThresholdSince;
  final DateTime? lastCatchUpExitAt;

  AdaptiveChunkingPolicyState copyWith({
    ChunkingMode? mode,
    DateTime? belowExitThresholdSince,
    bool clearBelowExitThresholdSince = false,
    DateTime? lastCatchUpExitAt,
    bool clearLastCatchUpExitAt = false,
  }) {
    return AdaptiveChunkingPolicyState(
      mode: mode ?? this.mode,
      belowExitThresholdSince: clearBelowExitThresholdSince
          ? null
          : (belowExitThresholdSince ?? this.belowExitThresholdSince),
      lastCatchUpExitAt: clearLastCatchUpExitAt
          ? null
          : (lastCatchUpExitAt ?? this.lastCatchUpExitAt),
    );
  }
}

class AdaptiveChunkingDecisionResult {
  const AdaptiveChunkingDecisionResult({
    required this.policy,
    required this.decision,
  });

  final AdaptiveChunkingPolicyState policy;
  final ChunkingDecision decision;
}

const _enterQueueDepthLines = 8;
const _enterOldestAge = Duration(milliseconds: 120);
const _exitQueueDepthLines = 2;
const _exitOldestAge = Duration(milliseconds: 40);
const _exitHold = Duration(milliseconds: 250);
const _reenterCatchUpHold = Duration(milliseconds: 250);
const _severeQueueDepthLines = 64;
const _severeOldestAge = Duration(milliseconds: 300);

AdaptiveChunkingDecisionResult decideAdaptiveChunking({
  required AdaptiveChunkingPolicyState policy,
  required QueueSnapshot snapshot,
  required DateTime now,
}) {
  var next = policy;

  if (snapshot.queuedLines == 0) {
    next = next.copyWith(
      mode: ChunkingMode.smooth,
      clearBelowExitThresholdSince: true,
      lastCatchUpExitAt: policy.mode == ChunkingMode.catchUp
          ? now
          : policy.lastCatchUpExitAt,
    );
    return AdaptiveChunkingDecisionResult(
      policy: next,
      decision: const ChunkingDecision(
        mode: ChunkingMode.smooth,
        enteredCatchUp: false,
        drainPlan: DrainPlan.single(),
      ),
    );
  }

  var enteredCatchUp = false;
  if (next.mode == ChunkingMode.smooth) {
    final canEnter = _shouldEnterCatchUp(snapshot);
    final severeBacklog = _isSevereBacklog(snapshot);
    final reentryHoldActive =
        next.lastCatchUpExitAt != null &&
        now.difference(next.lastCatchUpExitAt!) < _reenterCatchUpHold;
    if (canEnter && (!reentryHoldActive || severeBacklog)) {
      next = next.copyWith(
        mode: ChunkingMode.catchUp,
        clearBelowExitThresholdSince: true,
        clearLastCatchUpExitAt: true,
      );
      enteredCatchUp = true;
    }
  } else {
    if (_shouldExitCatchUp(snapshot)) {
      if (next.belowExitThresholdSince == null) {
        next = next.copyWith(belowExitThresholdSince: now);
      } else if (now.difference(next.belowExitThresholdSince!) >= _exitHold) {
        next = next.copyWith(
          mode: ChunkingMode.smooth,
          clearBelowExitThresholdSince: true,
          lastCatchUpExitAt: now,
        );
      }
    } else if (next.belowExitThresholdSince != null) {
      next = next.copyWith(clearBelowExitThresholdSince: true);
    }
  }

  final drainPlan = next.mode == ChunkingMode.catchUp
      ? DrainPlan.batch(snapshot.queuedLines.clamp(1, 200))
      : const DrainPlan.single();

  return AdaptiveChunkingDecisionResult(
    policy: next,
    decision: ChunkingDecision(
      mode: next.mode,
      enteredCatchUp: enteredCatchUp,
      drainPlan: drainPlan,
    ),
  );
}

bool _shouldEnterCatchUp(QueueSnapshot snapshot) {
  if (snapshot.queuedLines >= _enterQueueDepthLines) {
    return true;
  }
  final oldestAge = snapshot.oldestAge;
  return oldestAge != null && oldestAge >= _enterOldestAge;
}

bool _shouldExitCatchUp(QueueSnapshot snapshot) {
  if (snapshot.queuedLines > _exitQueueDepthLines) {
    return false;
  }
  final oldestAge = snapshot.oldestAge;
  return oldestAge == null || oldestAge <= _exitOldestAge;
}

bool _isSevereBacklog(QueueSnapshot snapshot) {
  if (snapshot.queuedLines >= _severeQueueDepthLines) {
    return true;
  }
  final oldestAge = snapshot.oldestAge;
  return oldestAge != null && oldestAge >= _severeOldestAge;
}
