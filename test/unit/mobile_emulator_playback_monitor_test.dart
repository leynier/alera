import 'dart:async';

import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_playback_monitor.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports player errors without treating them as completion', () {
    fakeAsync((clock) {
      final errors = StreamController<String>();
      final completions = StreamController<bool>();

      final warnings = <String>[];
      var recoveries = 0;
      final monitor = MobileEmulatorPlaybackMonitor(
        errors: errors.stream,
        completions: completions.stream,
        retryDelay: .zero,
        onWarning: warnings.add,
        onFailure: () => recoveries += 1,
      );

      completions.add(false);
      clock.flushMicrotasks();
      expect(recoveries, 0);

      errors.add('transient decoder warning');
      errors.add('repeated decoder warning');
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      expect(warnings, <String>['transient decoder warning']);
      expect(recoveries, 0);

      completions.add(true);
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      expect(recoveries, 1);
      unawaited(monitor.dispose());
      unawaited(errors.close());
      unawaited(completions.close());
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('does not recover after disposal', () {
    fakeAsync((clock) {
      final errors = StreamController<String>();
      final completions = StreamController<bool>();

      var recoveries = 0;
      final monitor = MobileEmulatorPlaybackMonitor(
        errors: errors.stream,
        completions: completions.stream,
        retryDelay: .zero,
        onWarning: (_) {},
        onFailure: () => recoveries += 1,
      );

      unawaited(monitor.dispose());
      clock.flushMicrotasks();
      errors.add('disposed');
      completions.add(true);
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);

      expect(recoveries, 0);
      unawaited(errors.close());
      unawaited(completions.close());
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('allows one automatic retry before playback is stable', () {
    final policy = MobileEmulatorPlaybackRecoveryPolicy();
    addTearDown(policy.dispose);

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.fail);
  });

  test('stable playback restores the automatic retry allowance', () {
    fakeAsync((clock) {
      final policy = MobileEmulatorPlaybackRecoveryPolicy(
        stabilityWindow: const Duration(milliseconds: 5),
      );
      addTearDown(policy.dispose);

      expect(
        policy.recordFailure(),
        MobileEmulatorPlaybackRecoveryAction.retry,
      );
      policy.playbackStarted();
      clock.elapse(const Duration(milliseconds: 5));

      expect(
        policy.recordFailure(),
        MobileEmulatorPlaybackRecoveryAction.retry,
      );
    });
  });

  test('explicit reset restores the automatic retry allowance', () {
    final policy = MobileEmulatorPlaybackRecoveryPolicy();
    addTearDown(policy.dispose);

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
    policy.reset();

    expect(policy.recordFailure(), MobileEmulatorPlaybackRecoveryAction.retry);
  });
}
