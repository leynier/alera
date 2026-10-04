import 'package:alera/src/features/automations/domain/automation_models.dart';

enum AutomationTone { info, success, warning, error, neutral }

class const AutomationStatusLabel({
  required final String label,
  required final AutomationTone tone,
  final bool inProgress = false,
});

AutomationStatusLabel automationStateLabel(AutomationRecord automation) =>
    switch (automation.state) {
      'active' => const AutomationStatusLabel(
        label: 'Active',
        tone: AutomationTone.success,
      ),
      'paused' => const AutomationStatusLabel(
        label: 'Paused',
        tone: AutomationTone.neutral,
      ),
      'blocked' => const AutomationStatusLabel(
        label: 'Needs Attention',
        tone: AutomationTone.warning,
      ),
      'archived' => const AutomationStatusLabel(
        label: 'Completed',
        tone: AutomationTone.neutral,
      ),
      'trashed' => const AutomationStatusLabel(
        label: 'Trash',
        tone: AutomationTone.neutral,
      ),
      _ => const AutomationStatusLabel(
        label: 'Draft',
        tone: AutomationTone.neutral,
      ),
    };

/// Human label for a run, including the recovery phase an older client would
/// read as plain running or queued.
AutomationStatusLabel automationRunStatusLabel(
  AutomationRunRecord run, {
  DateTime? now,
}) {
  final recovery = run.recovery;
  if (!run.isFinal && recovery.isActive) {
    final lastAttempt =
        recovery.maxAttempts > 0 && recovery.attempt >= recovery.maxAttempts;
    final tone = lastAttempt ? AutomationTone.warning : AutomationTone.info;
    return switch (recovery.status) {
      AutomationRecoveryStatus.reconnecting => AutomationStatusLabel(
        label: switch (recovery.code) {
          'ownerRunning' => 'Waiting For Previous Owner',
          'hostUnreachable' => 'Reconnecting To Host',
          _ => 'Reconnecting',
        },
        tone: tone,
        inProgress: true,
      ),
      AutomationRecoveryStatus.resuming => AutomationStatusLabel(
        label: 'Resuming Conversation',
        tone: tone,
        inProgress: true,
      ),
      _ => AutomationStatusLabel(
        label: recovery.maxAttempts > 0
            ? 'Retrying With Context · Attempt ${recovery.attempt} Of ${recovery.maxAttempts}'
            : 'Retrying With Context',
        tone: tone,
        inProgress: true,
      ),
    };
  }
  if (!run.isFinal && run.cancelRequestedAt != null) {
    return const AutomationStatusLabel(
      label: 'Cancelling',
      tone: AutomationTone.neutral,
      inProgress: true,
    );
  }
  return switch (run.status) {
    'pending' => AutomationStatusLabel(
      label: _retryLabel(run.retryAfter, now ?? DateTime.now()) ?? 'Queued',
      tone: AutomationTone.info,
      inProgress: true,
    ),
    'dispatching' => const AutomationStatusLabel(
      label: 'Starting',
      tone: AutomationTone.info,
      inProgress: true,
    ),
    'dispatched' => const AutomationStatusLabel(
      label: 'Running',
      tone: AutomationTone.info,
      inProgress: true,
    ),
    'waitingForUser' => const AutomationStatusLabel(
      label: 'Waiting For You',
      tone: AutomationTone.warning,
    ),
    'success' => const AutomationStatusLabel(
      label: 'Succeeded',
      tone: AutomationTone.success,
    ),
    'failure' => const AutomationStatusLabel(
      label: 'Failed',
      tone: AutomationTone.error,
    ),
    'timeout' => const AutomationStatusLabel(
      label: 'Timed Out',
      tone: AutomationTone.error,
    ),
    'blocked' => const AutomationStatusLabel(
      label: 'Blocked',
      tone: AutomationTone.warning,
    ),
    'cancelled' => const AutomationStatusLabel(
      label: 'Cancelled',
      tone: AutomationTone.neutral,
    ),
    'precheckSkipped' => const AutomationStatusLabel(
      label: 'Skipped: Precheck',
      tone: AutomationTone.neutral,
    ),
    'misfireSkipped' => const AutomationStatusLabel(
      label: 'Missed While Runtime Was Off',
      tone: AutomationTone.neutral,
    ),
    'overlapSkipped' => const AutomationStatusLabel(
      label: 'Skipped: Previous Run Active',
      tone: AutomationTone.neutral,
    ),
    'queueLimitSkipped' => const AutomationStatusLabel(
      label: 'Skipped: Queue Full',
      tone: AutomationTone.neutral,
    ),
    final other => AutomationStatusLabel(
      label: other.isEmpty ? 'Unknown' : other,
      tone: AutomationTone.neutral,
    ),
  };
}

String? _retryLabel(DateTime? retryAfter, DateTime now) {
  if (retryAfter == null || !retryAfter.isAfter(now)) return null;
  return 'Next Attempt In ${automationShortDuration(retryAfter.difference(now))}';
}

String automationShortDuration(Duration duration) {
  if (duration.inDays > 0) return '${duration.inDays}d';
  if (duration.inHours > 0) return '${duration.inHours}h';
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return '${duration.inSeconds.clamp(1, 59)}s';
}

/// "in 3h" / "5m ago" style relative time used in lists.
String automationRelativeTime(DateTime moment, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = moment.difference(reference);
  if (difference.inSeconds.abs() < 60) return 'now';
  final label = automationShortDuration(difference.abs());
  return difference.isNegative ? '$label ago' : 'in $label';
}

/// Consecutive missed occurrences collapse into one row: the runtime records
/// one run per missed occurrence, which would otherwise flood the history.
sealed class AutomationRunHistoryEntry {
  const AutomationRunHistoryEntry();
}

final class AutomationRunHistoryRun extends AutomationRunHistoryEntry {
  const AutomationRunHistoryRun(this.run);
  final AutomationRunRecord run;
}

final class AutomationRunHistoryMissed extends AutomationRunHistoryEntry {
  const AutomationRunHistoryMissed(this.runs);
  final List<AutomationRunRecord> runs;

  DateTime? get from => runs
      .map((run) => run.scheduledAt)
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (value, item) => value == null || item.isBefore(value) ? item : value,
      );

  DateTime? get to => runs
      .map((run) => run.scheduledAt)
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (value, item) => value == null || item.isAfter(value) ? item : value,
      );
}

List<AutomationRunHistoryEntry> automationRunHistory(
  List<AutomationRunRecord> runs,
) {
  final entries = <AutomationRunHistoryEntry>[];
  var missed = <AutomationRunRecord>[];
  void flush() {
    if (missed.isEmpty) return;
    entries.add(
      missed.length == 1
          ? AutomationRunHistoryRun(missed.single)
          : AutomationRunHistoryMissed(List.unmodifiable(missed)),
    );
    missed = <AutomationRunRecord>[];
  }

  for (final run in runs) {
    if (run.status == 'misfireSkipped') {
      missed.add(run);
      continue;
    }
    flush();
    entries.add(AutomationRunHistoryRun(run));
  }
  flush();
  return entries;
}

/// A final run whose remote owner never confirmed it stopped keeps its target
/// reserved, so no later run can start a duplicate there.
const String automationOwnerReservedMessage =
    'Owner Reserved · Waiting For Reconciliation. New runs to this target wait until the previous owner is confirmed stopped.';
