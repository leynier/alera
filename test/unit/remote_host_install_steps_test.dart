import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps every stage the runtime emits to a step', () {
    expect(
      <String>[for (final (stage, _) in remoteHostInstallStages) stage],
      <String>[
        'auth',
        'detect',
        'artifact',
        'upload',
        'install',
        'validate',
        'restart',
        'prune',
      ],
    );
    expect(remoteHostInstallStageIndex('upload'), 3);
    expect(remoteHostInstallStageIndex('installing'), isNull);
  });

  test('a running install marks earlier steps done and the current active', () {
    final progress = _apply(<SshTargetBootstrapProgress>[
      _event('auth'),
      _event('detect'),
      _event('artifact'),
      _event('upload', fraction: 0.25),
    ]);

    final steps = progress.steps;
    expect(steps.map((step) => step.label), <String>[
      'Authenticate',
      'Detect platform',
      'Resolve runtime artifact',
      'Upload runtime',
      'Install runtime',
      'Validate runtime',
    ]);
    expect(steps.map((step) => step.state), <RemoteHostInstallStepState>[
      .done,
      .done,
      .done,
      .active,
      .pending,
      .pending,
    ]);
    expect(steps[3].progress, 0.25);
    expect(steps[3].detail, isNull);
    expect(progress.phaseLabel, 'Upload runtime');
    expect(progress.isRunning, isTrue);
  });

  test('an unknown stage keeps the step and shows the runtime message', () {
    final progress = _apply(<SshTargetBootstrapProgress>[
      _event('upload'),
      _event('checksum', message: 'Verifying Runtime Checksum'),
    ]);

    expect(progress.stageIndex, 3);
    expect(progress.steps[3].state, RemoteHostInstallStepState.active);
    expect(progress.steps[3].detail, 'Verifying Runtime Checksum');
  });

  test('installed marks every step done', () {
    final progress = _apply(<SshTargetBootstrapProgress>[
      _event('auth'),
      _event('validate'),
      _event('installed', status: .installed),
    ]);

    expect(
      progress.steps.every(
        (step) => step.state == RemoteHostInstallStepState.done,
      ),
      isTrue,
    );
    expect(progress.succeeded, isTrue);
  });

  test('failed marks the current step with the reason that came first', () {
    final progress = _apply(<SshTargetBootstrapProgress>[
      _event('auth'),
      _event('detect'),
      _event('failed', status: .failed, error: 'uname not found'),
      // The job's final event repeats the failure without a reason.
      _event('failed', status: .failed),
    ]);

    final steps = progress.steps;
    expect(steps[0].state, RemoteHostInstallStepState.done);
    expect(steps[1].state, RemoteHostInstallStepState.failed);
    expect(steps[1].detail, 'uname not found');
    expect(steps[2].state, RemoteHostInstallStepState.pending);
    expect(progress.failed, isTrue);
  });

  test('cancelled skips the remaining steps', () {
    final progress = _apply(<SshTargetBootstrapProgress>[
      _event('upload'),
      _event('cancelled', status: .cancelled),
    ]);

    final steps = progress.steps;
    expect(steps[2].state, RemoteHostInstallStepState.done);
    expect(steps[3].state, RemoteHostInstallStepState.skipped);
    expect(steps[3].detail, remoteHostInstallCancelledDetail);
    expect(steps[5].state, RemoteHostInstallStepState.skipped);
    expect(steps[5].detail, isNull);
  });

  test('restart stages add the update steps', () {
    final plain = _apply(<SshTargetBootstrapProgress>[_event('validate')]);
    expect(plain.steps, hasLength(6));

    final update = RemoteHostInstallProgress(
      targetId: 'mac',
      jobId: 'job-1',
      includesRestart: true,
    );
    expect(update.steps.map((step) => step.label).skip(6), <String>[
      'Restart runtime',
      'Remove old versions',
    ]);

    final restarted = plain.apply(_event('restart'));
    expect(restarted.steps, hasLength(8));
    expect(restarted.steps[6].state, RemoteHostInstallStepState.active);
  });

  test('a new job resets the progress', () {
    final first = _apply(<SshTargetBootstrapProgress>[
      _event('validate'),
      _event('failed', status: .failed, error: 'boom'),
    ]);
    final retried = first.apply(_event('auth', jobId: 'job-2'));

    expect(retried.jobId, 'job-2');
    expect(retried.error, isNull);
    expect(retried.stageIndex, 0);
    expect(retried.isRunning, isTrue);
  });

  test('a job found after a restart resumes at its stage', () {
    final progress = RemoteHostInstallProgress.fromJob(
      const SshTargetBootstrapJob(
        jobId: 'job-1',
        targetId: 'mac',
        status: .installing,
        stage: 'install',
      ),
    );
    expect(progress.stageIndex, 4);
    expect(progress.steps[4].state, RemoteHostInstallStepState.active);

    final withoutStage = RemoteHostInstallProgress.fromJob(
      const SshTargetBootstrapJob(
        jobId: 'job-1',
        targetId: 'mac',
        status: .installing,
      ),
    );
    expect(withoutStage.stageIndex, 0);
  });

  test('ignores events for another host', () {
    final progress = _apply(<SshTargetBootstrapProgress>[_event('upload')]);
    expect(progress.apply(_event('validate', targetId: 'other')).stageIndex, 3);
  });
}

RemoteHostInstallProgress _apply(List<SshTargetBootstrapProgress> events) {
  var progress = RemoteHostInstallProgress.fromProgress(events.first);
  for (final event in events.skip(1)) {
    progress = progress.apply(event);
  }
  return progress;
}

SshTargetBootstrapProgress _event(
  String stage, {
  SshBootstrapStatus status = SshBootstrapStatus.installing,
  String message = 'Working',
  String? error,
  double? fraction,
  String jobId = 'job-1',
  String targetId = 'mac',
}) {
  return SshTargetBootstrapProgress(
    jobId: jobId,
    targetId: targetId,
    status: status,
    stage: stage,
    message: message,
    error: error,
    progress: fraction,
  );
}
