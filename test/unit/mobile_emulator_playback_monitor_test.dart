import 'dart:async';

import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_playback_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports player errors without treating them as completion', () async {
    final errors = StreamController<String>();
    final completions = StreamController<bool>();
    addTearDown(errors.close);
    addTearDown(completions.close);
    final warnings = <String>[];
    var recoveries = 0;
    final monitor = MobileEmulatorPlaybackMonitor(
      errors: errors.stream,
      completions: completions.stream,
      retryDelay: Duration.zero,
      onWarning: warnings.add,
      onFailure: () => recoveries += 1,
    );
    addTearDown(monitor.dispose);

    completions.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(recoveries, 0);

    errors.add('transient decoder warning');
    errors.add('repeated decoder warning');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(warnings, <String>['transient decoder warning']);
    expect(recoveries, 0);

    completions.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(recoveries, 1);
  });

  test('does not recover after disposal', () async {
    final errors = StreamController<String>();
    final completions = StreamController<bool>();
    addTearDown(errors.close);
    addTearDown(completions.close);
    var recoveries = 0;
    final monitor = MobileEmulatorPlaybackMonitor(
      errors: errors.stream,
      completions: completions.stream,
      retryDelay: Duration.zero,
      onWarning: (_) {},
      onFailure: () => recoveries += 1,
    );

    await monitor.dispose();
    errors.add('disposed');
    completions.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(recoveries, 0);
  });

  test('allows one automatic retry before playback is stable', () {
    final policy = MobileEmulatorPlaybackRecoveryPolicy();
    addTearDown(policy.dispose);

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.fail);
  });

  test('stable playback restores the automatic retry allowance', () async {
    final policy = MobileEmulatorPlaybackRecoveryPolicy(
      stabilityWindow: const Duration(milliseconds: 5),
    );
    addTearDown(policy.dispose);

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
    policy.playbackStarted();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
  });

  test('explicit reset restores the automatic retry allowance', () {
    final policy = MobileEmulatorPlaybackRecoveryPolicy();
    addTearDown(policy.dispose);

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
    policy.reset();

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
  });
}
