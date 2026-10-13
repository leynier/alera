import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_snapshot.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';

/// A status as a badge shows it.
class const RunStatusLabel(final String label, final AleraBadgeTone tone);

/// Run statuses, with Needs Attention taking over from Running and Paused
/// when the runtime put the run in the attention bucket.
RunStatusLabel runStatusLabel(RunSummary run) {
  final attention = run.bucket == RunBucket.attention && !run.finished;
  return switch (run.status) {
    'planning' when !attention => const RunStatusLabel(
      'Planning',
      AleraBadgeTone.neutral,
    ),
    'awaitingApproval' => const RunStatusLabel(
      'Plan Awaiting Approval',
      AleraBadgeTone.attention,
    ),
    'completed' => const RunStatusLabel('Completed', AleraBadgeTone.success),
    'failed' => const RunStatusLabel('Failed', AleraBadgeTone.error),
    'cancelled' when run.completedAt == null => const RunStatusLabel(
      'Cancelling',
      AleraBadgeTone.attention,
    ),
    'cancelled' => const RunStatusLabel('Cancelled', AleraBadgeTone.neutral),
    _ when attention => const RunStatusLabel(
      'Needs Attention',
      AleraBadgeTone.attention,
    ),
    'paused' => const RunStatusLabel('Paused', AleraBadgeTone.neutral),
    'running' => const RunStatusLabel('Running', AleraBadgeTone.info),
    'planning' => const RunStatusLabel('Planning', AleraBadgeTone.neutral),
    final other => RunStatusLabel(other, AleraBadgeTone.neutral),
  };
}

/// Task statuses; an isolated attempt's state wins over the task status.
RunStatusLabel taskStatusLabel(String status) => switch (status) {
  'pending' ||
  'queued' ||
  'reserved' => const RunStatusLabel('Queued', AleraBadgeTone.neutral),
  'ready' => const RunStatusLabel('Ready', AleraBadgeTone.neutral),
  'starting' => const RunStatusLabel('Starting', AleraBadgeTone.neutral),
  'running' ||
  'dispatched' ||
  'started' => const RunStatusLabel('Running', AleraBadgeTone.info),
  'result_ready' ||
  'resultReady' => const RunStatusLabel('Result Ready', AleraBadgeTone.info),
  'integrated' => const RunStatusLabel('Integrated', AleraBadgeTone.success),
  'completed' => const RunStatusLabel('Completed', AleraBadgeTone.success),
  'blocked' => const RunStatusLabel('Blocked', AleraBadgeTone.attention),
  'stalled' => const RunStatusLabel('Stalled', AleraBadgeTone.attention),
  'attention' => const RunStatusLabel(
    'Needs Attention',
    AleraBadgeTone.attention,
  ),
  'failed' => const RunStatusLabel('Failed', AleraBadgeTone.error),
  'conflict' => const RunStatusLabel('Conflict', AleraBadgeTone.error),
  'refused' => const RunStatusLabel('Needs Correction', AleraBadgeTone.error),
  'cancelled' ||
  'canceled' => const RunStatusLabel('Cancelled', AleraBadgeTone.neutral),
  final other => RunStatusLabel(other, AleraBadgeTone.neutral),
};

/// The state a task row shows: the attempt state for isolated runs.
String taskDisplayState(RunTask task) => task.attemptState ?? task.status;

String runGateKindLabel(RunGateKind kind) => switch (kind) {
  RunGateKind.decision => 'Decision',
  RunGateKind.stall => 'Stall',
  RunGateKind.plan => 'Plan Approval',
  RunGateKind.stage => 'Stage Gate',
};

/// `foundation` and `product` recipe gates name what they guard.
String? stageGateKindLabel(String? gateKind) => switch (gateKind) {
  'foundation' => 'Foundation',
  'product' => 'Product',
  _ => null,
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
};

/// Why a run sits in Attention, for list rows and the status-bar card.
String? runAttentionLabel(RunSummary run) {
  final kinds = run.pendingGateKinds;
  if (kinds.contains('plan') || run.planGatePending) return 'Plan approval';
  if (kinds.contains('stage')) return 'Stage gate';
  if (kinds.contains('decision')) return 'Decision needed';
  if (kinds.contains('stall') || run.stalledCount > 0) return 'Stalled task';
  if (run.failedCount > 0) return 'Failed task';
  if (run.blockedCount > 0) return 'Blocked task';
  if (run.coordinatorState == 'attention') return 'Coordinator attention';
  if (run.cleanupAttention) return 'Cleanup attention';
  final reason = run.attentionReason?.trim();
  if (reason != null && reason.isNotEmpty) return reason;
  return null;
}

String runIsolationLabel(String isolation) =>
    isolation == 'isolated' ? 'Isolated' : 'Shared';

String runActorLabel(String? kind, String? id) => switch (kind) {
  'desktop' => 'you',
  'mobile' => id == null ? 'a phone' : 'phone $id',
  'cli' => 'the CLI',
  'mcp' => id ?? 'an MCP client',
  'agent' => id ?? 'an agent',
  'runtime' => 'Alera',
  _ => id ?? 'someone',
};

String shortSha(String? sha) =>
    sha == null ? '' : (sha.length > 7 ? sha.substring(0, 7) : sha);

/// `4m ago`, `2h ago`, `3d ago`, then the date.
String runAgeLabel(String? iso, DateTime now) {
  final value = parseRunTimestamp(iso)?.toLocal();
  if (value == null) return '';
  final age = now.difference(value);
  if (age < const Duration(minutes: 1)) return 'just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes}m ago';
  if (age < const Duration(days: 1)) return '${age.inHours}h ago';
  if (age < const Duration(days: 7)) return '${age.inDays}d ago';
  return runDateLabel(value);
}

/// `14:02` in local time.
String runClockLabel(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// `Today`, `Yesterday`, else the date.
String runDayLabel(DateTime value, DateTime now) {
  final local = value.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return runDateLabel(local);
}

String runDateLabel(DateTime value) =>
    '${value.year}-${_two(value.month)}-${_two(value.day)}';

String _two(int value) => value.toString().padLeft(2, '0');
