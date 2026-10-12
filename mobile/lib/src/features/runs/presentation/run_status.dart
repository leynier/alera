import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';

/// A status word and the badge tone it reads in. The same vocabulary as the
/// desktop's Activity, so a run reads the same on both.
class const RunStatusLabel(final String label, final AleraBadgeTone tone);

/// Run status. A finished run keeps its own word; an unfinished one in the
/// attention bucket reads Needs Attention whatever its raw status.
RunStatusLabel runStatusLabel(RunSummary run) {
  if (run.status == 'failed') {
    return const RunStatusLabel('Failed', AleraBadgeTone.error);
  }
  if (run.isCancelling) {
    return const RunStatusLabel('Cancelling', AleraBadgeTone.attention);
  }
  if (run.status == 'completed') {
    return const RunStatusLabel('Completed', AleraBadgeTone.success);
  }
  if (run.status == 'cancelled') {
    return const RunStatusLabel('Cancelled', AleraBadgeTone.neutral);
  }
  if (run.status == 'awaitingApproval' || run.planGatePending) {
    return const RunStatusLabel(
      'Plan Awaiting Approval',
      AleraBadgeTone.attention,
    );
  }
  if (run.bucket == RunBucket.attention) {
    return const RunStatusLabel('Needs Attention', AleraBadgeTone.attention);
  }
  return switch (run.status) {
    'planning' => const RunStatusLabel('Planning', AleraBadgeTone.neutral),
    'paused' => const RunStatusLabel('Paused', AleraBadgeTone.neutral),
    'running' => const RunStatusLabel('Running', AleraBadgeTone.info),
    _ => RunStatusLabel(_titleCase(run.status), AleraBadgeTone.neutral),
  };
}

/// Task status. Terminal task states win; an isolated attempt's progress
/// explains everything in between.
RunStatusLabel runTaskStatusLabel(String status, {String? attemptState}) {
  switch (status) {
    case 'failed':
      return const RunStatusLabel('Failed', AleraBadgeTone.error);
    case 'cancelled':
      return const RunStatusLabel('Cancelled', AleraBadgeTone.neutral);
    case 'blocked':
      return const RunStatusLabel('Blocked', AleraBadgeTone.attention);
  }
  final attempt = switch (attemptState) {
    'reserved' => const RunStatusLabel('Queued', AleraBadgeTone.neutral),
    'ready' => const RunStatusLabel('Ready', AleraBadgeTone.neutral),
    'starting' => const RunStatusLabel('Starting', AleraBadgeTone.neutral),
    'started' => const RunStatusLabel('Running', AleraBadgeTone.info),
    'result_ready' => const RunStatusLabel('Result Ready', AleraBadgeTone.info),
    'integrated' => const RunStatusLabel('Integrated', AleraBadgeTone.success),
    'conflict' => const RunStatusLabel('Conflict', AleraBadgeTone.error),
    'refused' => const RunStatusLabel('Needs Correction', AleraBadgeTone.error),
    'attention' => const RunStatusLabel(
      'Needs Attention',
      AleraBadgeTone.attention,
    ),
    'stalled' => const RunStatusLabel('Stalled', AleraBadgeTone.attention),
    'cancelled' => const RunStatusLabel('Cancelled', AleraBadgeTone.neutral),
    _ => null,
  };
  if (attempt != null) return attempt;
  return switch (status) {
    'pending' => const RunStatusLabel('Queued', AleraBadgeTone.neutral),
    'ready' => const RunStatusLabel('Ready', AleraBadgeTone.neutral),
    'dispatched' => const RunStatusLabel('Running', AleraBadgeTone.info),
    'completed' => const RunStatusLabel('Completed', AleraBadgeTone.success),
    'stalled' => const RunStatusLabel('Stalled', AleraBadgeTone.attention),
    _ => RunStatusLabel(_titleCase(status), AleraBadgeTone.neutral),
  };
}

/// Gate kind: Decision, Stall, Plan Approval, or Stage Gate with its stage.
String runGateKindLabel(RunGate gate) => switch (gate.kind) {
  RunGateKind.decision => 'Decision',
  RunGateKind.stall => 'Stall',
  RunGateKind.plan => 'Plan Approval',
  RunGateKind.stage =>
    gate.scope.isEmpty
        ? 'Stage Gate'
        : 'Stage Gate · ${_titleCase(gate.scope)}',
  RunGateKind.unknown => 'Gate',
};

RunStatusLabel runGateStatusLabel(RunGateStatus status) => switch (status) {
  RunGateStatus.pending => const RunStatusLabel(
    'Pending',
    AleraBadgeTone.attention,
  ),
  RunGateStatus.resolved => const RunStatusLabel(
    'Resolved',
    AleraBadgeTone.success,
  ),
  RunGateStatus.timeout => const RunStatusLabel(
    'Expired',
    AleraBadgeTone.neutral,
  ),
  RunGateStatus.invalidated => const RunStatusLabel(
    'Invalidated',
    AleraBadgeTone.neutral,
  ),
  RunGateStatus.unknown => const RunStatusLabel(
    'Unknown',
    AleraBadgeTone.neutral,
  ),
};

/// Button label of a gate option id.
String runGateOptionLabel(RunGate gate, String option) => switch (option) {
  'approve' => gate.kind == RunGateKind.plan ? 'Approve Plan' : 'Approve Gate',
  'requestChanges' => 'Request Changes',
  'reject' => 'Reject',
  'killAndFailover' => 'Kill And Failover',
  'keepWaiting' => 'Keep Waiting',
  'abortStage' => 'Abort Stage',
  _ => option,
};

/// Short age such as `4m ago`; older than a week shows the date.
String runAgeLabel(DateTime? value, DateTime now) {
  if (value == null) return '';
  final age = now.difference(value);
  if (age < const Duration(minutes: 1)) return 'just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes}m ago';
  if (age < const Duration(days: 1)) return '${age.inHours}h ago';
  if (age < const Duration(days: 7)) return '${age.inDays}d ago';
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

/// `Isolated · 4/9 tasks`.
String runProgressLabel(RunSummary run) {
  final parts = <String>[run.isolation.label];
  if (run.taskCount > 0) {
    parts.add('${run.completedCount}/${run.taskCount} tasks');
  }
  return parts.join(' · ');
}

/// What needs a person, shortest first: `1 gate`, `2 stalled`.
String? runAttentionSummary(RunSummary run) {
  final parts = <String>[
    if (run.pendingGateCount > 0)
      run.pendingGateCount == 1 ? '1 gate' : '${run.pendingGateCount} gates',
    if (run.failedCount > 0) '${run.failedCount} failed',
    if (run.stalledCount > 0) '${run.stalledCount} stalled',
    if (run.blockedCount > 0) '${run.blockedCount} blocked',
    if (run.cleanupAttention) 'cleanup needs attention',
  ];
  return parts.isEmpty ? run.attentionReason : parts.join(' · ');
}

String shortSha(String? sha) =>
    sha == null || sha.length <= 8 ? sha ?? '' : sha.substring(0, 8);

String _two(int value) => value.toString().padLeft(2, '0');

String _titleCase(String value) {
  final words = value
      .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp('[_-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty);
  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
