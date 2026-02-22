import 'package:alera/src/features/session/application/streaming/adaptive_chunking_policy.dart';

enum CommitTickScope { anyMode, catchUpOnly }

class StreamQueuedLine {
  const StreamQueuedLine({
    required this.turnId,
    required this.text,
    required this.enqueuedAt,
    this.itemId,
    this.streamPhase = 'unknown',
    this.isSoftChunk = false,
    this.appendWithoutNewline = false,
  });

  final String turnId;
  final String text;
  final DateTime enqueuedAt;
  final String? itemId;
  final String streamPhase;
  final bool isSoftChunk;
  final bool appendWithoutNewline;
}

class CommitTickResult {
  const CommitTickResult({
    required this.policy,
    required this.remainingQueue,
    required this.drainedLines,
    required this.queueDepth,
    required this.oldestAgeMs,
    required this.allIdle,
  });

  final AdaptiveChunkingPolicyState policy;
  final List<StreamQueuedLine> remainingQueue;
  final List<StreamQueuedLine> drainedLines;
  final int queueDepth;
  final int? oldestAgeMs;
  final bool allIdle;
}

CommitTickResult runCommitTick({
  required AdaptiveChunkingPolicyState policy,
  required List<StreamQueuedLine> queue,
  required CommitTickScope scope,
  required DateTime now,
}) {
  final snapshot = _snapshot(queue, now: now);
  final decisionResult = decideAdaptiveChunking(
    policy: policy,
    snapshot: snapshot,
    now: now,
  );
  final decision = decisionResult.decision;

  if (scope == CommitTickScope.catchUpOnly &&
      decision.mode != ChunkingMode.catchUp) {
    return CommitTickResult(
      policy: decisionResult.policy,
      remainingQueue: List<StreamQueuedLine>.unmodifiable(queue),
      drainedLines: const <StreamQueuedLine>[],
      queueDepth: queue.length,
      oldestAgeMs: snapshot.oldestAge?.inMilliseconds,
      allIdle: queue.isEmpty,
    );
  }

  final toDrain = decision.drainPlan.isBatch ? decision.drainPlan.maxLines : 1;
  final safeDrainCount = toDrain.clamp(0, queue.length);
  final drained = safeDrainCount == 0
      ? const <StreamQueuedLine>[]
      : queue.sublist(0, safeDrainCount);
  final remaining = safeDrainCount == queue.length
      ? const <StreamQueuedLine>[]
      : queue.sublist(safeDrainCount);
  final remainingSnapshot = _snapshot(remaining, now: now);

  return CommitTickResult(
    policy: decisionResult.policy,
    remainingQueue: List<StreamQueuedLine>.unmodifiable(remaining),
    drainedLines: List<StreamQueuedLine>.unmodifiable(drained),
    queueDepth: remaining.length,
    oldestAgeMs: remainingSnapshot.oldestAge?.inMilliseconds,
    allIdle: remaining.isEmpty,
  );
}

QueueSnapshot _snapshot(List<StreamQueuedLine> queue, {required DateTime now}) {
  if (queue.isEmpty) {
    return const QueueSnapshot(queuedLines: 0, oldestAge: null);
  }
  Duration? oldestAge;
  for (final line in queue) {
    final age = now.difference(line.enqueuedAt);
    if (oldestAge == null || age > oldestAge) {
      oldestAge = age;
    }
  }
  return QueueSnapshot(queuedLines: queue.length, oldestAge: oldestAge);
}
