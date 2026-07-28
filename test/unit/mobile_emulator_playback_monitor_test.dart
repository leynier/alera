import 'dart:async';

import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_playback_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovers once when a ready player later fails', () async {
    final errors = StreamController<String>();
    final completions = StreamController<bool>();
    addTearDown(errors.close);
    addTearDown(completions.close);
    var recoveries = 0;
    final monitor = MobileEmulatorPlaybackMonitor(
      errors: errors.stream,
      completions: completions.stream,
      retryDelay: Duration.zero,
      onFailure: () => recoveries += 1,
    );
    addTearDown(monitor.dispose);

    completions.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(recoveries, 0);

    errors.add('stream ended');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(recoveries, 1);

    completions.add(true);
    await Future<void>.delayed(Duration.zero);
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
      onFailure: () => recoveries += 1,
    );

    await monitor.dispose();
    errors.add('disposed');
    completions.add(true);
    await Future<void>.delayed(Duration.zero);

    expect(recoveries, 0);
  });
}
