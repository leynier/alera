import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

/// Mirrors `AleraProgressStepState` so the domain stays free of widgets.
enum RemoteHostInstallStepState { pending, active, done, failed, skipped }

class const RemoteHostInstallStep({
  required final String label,
  final String? detail,
  final RemoteHostInstallStepState state = RemoteHostInstallStepState.pending,
  final double? progress,
});

/// The stages `sshTarget.bootstrap.start` reports, in order, with the label
/// each one shows. `restart` and `prune` only run when the install also
/// restarts the runtime (Update Runtime).
const List<(String, String)> remoteHostInstallStages = <(String, String)>[
  ('auth', 'Authenticate'),
  ('detect', 'Detect platform'),
  ('artifact', 'Resolve runtime artifact'),
  ('upload', 'Upload runtime'),
  ('install', 'Install runtime'),
  ('validate', 'Validate runtime'),
  ('restart', 'Restart runtime'),
  ('prune', 'Remove old versions'),
];

const int _firstRestartStage = 6;

const String remoteHostInstallCancelledDetail = 'Install cancelled';

int? remoteHostInstallStageIndex(String stage) {
  for (final (index, (name, _)) in remoteHostInstallStages.indexed) {
    if (name == stage) {
      return index;
    }
  }
  return null;
}

/// Install progress for one host, accumulated from
/// `sshTargetBootstrapProgress` events. A stage this app does not know keeps
/// the current step and shows the runtime's message as its detail; the
/// terminal stages (`installed`, `failed`, `cancelled`) arrive through
/// [status].
class const RemoteHostInstallProgress({
  required final String targetId,
  final String? jobId,
  final SshBootstrapStatus status = SshBootstrapStatus.installing,
  final int stageIndex = 0,
  final String? message,
  final String? error,
  final String? unknownStageDetail,
  final double? fraction,
  final bool includesRestart = false,
}) {
  factory fromProgress(
    SshTargetBootstrapProgress progress, {
    bool includesRestart = false,
  }) {
    return RemoteHostInstallProgress(
      targetId: progress.targetId,
      jobId: progress.jobId,
      includesRestart: includesRestart,
    ).apply(progress);
  }

  /// A job the runtime reports as running before any progress event arrived,
  /// such as one found by `sshTarget.bootstrap.jobs` after a restart.
  factory fromJob(SshTargetBootstrapJob job) {
    final index = job.stage == null
        ? null
        : remoteHostInstallStageIndex(job.stage!);
    return RemoteHostInstallProgress(
      targetId: job.targetId,
      jobId: job.jobId,
      status: job.status,
      stageIndex: index ?? 0,
      includesRestart: index != null && index >= _firstRestartStage,
    );
  }

  bool get isRunning => status == SshBootstrapStatus.installing;

  bool get failed => status == SshBootstrapStatus.failed;

  bool get cancelled => status == SshBootstrapStatus.cancelled;

  bool get succeeded => status == SshBootstrapStatus.installed;

  /// Label of the step in progress, for job cards and status lines.
  String get phaseLabel => remoteHostInstallStages[stageIndex].$2;

  /// The latest event this progress stands for, for
  /// `RemoteHostStatus.derive`.
  SshTargetBootstrapProgress toBootstrapProgress() {
    return SshTargetBootstrapProgress(
      jobId: jobId ?? '',
      targetId: targetId,
      status: status,
      stage: remoteHostInstallStages[stageIndex].$1,
      message: message ?? '',
      error: error,
      progress: fraction,
    );
  }

  RemoteHostInstallProgress apply(SshTargetBootstrapProgress progress) {
    if (progress.targetId != targetId) {
      return this;
    }
    final sameJob =
        jobId == null ||
        jobId!.isEmpty ||
        progress.jobId.isEmpty ||
        progress.jobId == jobId;
    final base = sameJob
        ? this
        : RemoteHostInstallProgress(
            targetId: targetId,
            jobId: progress.jobId,
            includesRestart: includesRestart,
          );
    final index = remoteHostInstallStageIndex(progress.stage);
    final running = progress.status == SshBootstrapStatus.installing;
    return RemoteHostInstallProgress(
      targetId: targetId,
      jobId: progress.jobId.isEmpty ? base.jobId : progress.jobId,
      status: progress.status,
      stageIndex: index ?? base.stageIndex,
      message: progress.message,
      // The runtime reports a failure twice, and only the first event carries
      // the reason, so a later event without one must not erase it.
      error: progress.error ?? base.error,
      unknownStageDetail: index == null && running
          ? progress.message
          : (index == null ? base.unknownStageDetail : null),
      fraction: index == null ? base.fraction : progress.progress,
      includesRestart:
          base.includesRestart ||
          (index != null && index >= _firstRestartStage),
    );
  }

  List<RemoteHostInstallStep> get steps {
    final count = includesRestart
        ? remoteHostInstallStages.length
        : _firstRestartStage;
    return <RemoteHostInstallStep>[
      for (var index = 0; index < count; index++) _step(index),
    ];
  }

  RemoteHostInstallStep _step(int index) {
    final label = remoteHostInstallStages[index].$2;
    if (status == SshBootstrapStatus.installed || index < stageIndex) {
      return RemoteHostInstallStep(
        label: label,
        state: RemoteHostInstallStepState.done,
      );
    }
    switch (status) {
      case SshBootstrapStatus.installing:
        return index == stageIndex
            ? RemoteHostInstallStep(
                label: label,
                detail: unknownStageDetail,
                state: RemoteHostInstallStepState.active,
                progress: fraction,
              )
            : RemoteHostInstallStep(label: label);
      case SshBootstrapStatus.failed:
        return index == stageIndex
            ? RemoteHostInstallStep(
                label: label,
                detail: error ?? message,
                state: RemoteHostInstallStepState.failed,
              )
            : RemoteHostInstallStep(label: label);
      case SshBootstrapStatus.cancelled:
        return RemoteHostInstallStep(
          label: label,
          detail: index == stageIndex ? remoteHostInstallCancelledDetail : null,
          state: RemoteHostInstallStepState.skipped,
        );
      case _:
        return RemoteHostInstallStep(label: label);
    }
  }
}
