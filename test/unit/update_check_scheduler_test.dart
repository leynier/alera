import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/updater/application/update_check_scheduler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeForeground implements AppForeground {
  _FakeForeground({this.isForeground = true});

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  bool isForeground;

  @override
  Stream<bool> get changes => _changes.stream;

  void emit(bool value) {
    isForeground = value;
    _changes.add(value);
  }

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}

void main() {
  group('AleraUpdateCheckScheduler', () {
    test('checks immediately when the window is already visible', () {
      fakeAsync((async) {
        var checks = 0;
        final foreground = _FakeForeground();
        final scheduler = AleraUpdateCheckScheduler(
          check: () async => checks++,
          foreground: foreground,
          interval: const Duration(minutes: 15),
        );
        async.flushMicrotasks();

        expect(checks, 1);

        async.elapse(const Duration(minutes: 15));
        expect(checks, 2);
        async.elapse(const Duration(minutes: 30));
        expect(checks, 4);

        scheduler.dispose();
        foreground.dispose();
      });
    });

    test('parks while hidden and checks again on return', () {
      fakeAsync((async) {
        var checks = 0;
        final foreground = _FakeForeground();
        final scheduler = AleraUpdateCheckScheduler(
          check: () async => checks++,
          foreground: foreground,
          interval: const Duration(minutes: 15),
        );
        async.flushMicrotasks();
        expect(checks, 1);

        foreground.emit(false);
        async.flushMicrotasks();
        expect(scheduler.isRunning, isFalse);

        // A hidden window must not spend a check nobody can see the result of.
        async.elapse(const Duration(hours: 2));
        expect(checks, 1);

        foreground.emit(true);
        async.flushMicrotasks();
        // Coming back checks straight away rather than waiting out a fresh
        // interval, which is when a release is most likely to be waiting.
        expect(checks, 2);
        expect(scheduler.isRunning, isTrue);

        scheduler.dispose();
        foreground.dispose();
      });
    });

    test('does not start while the window starts hidden', () {
      fakeAsync((async) {
        var checks = 0;
        final foreground = _FakeForeground(isForeground: false);
        final scheduler = AleraUpdateCheckScheduler(
          check: () async => checks++,
          foreground: foreground,
          interval: const Duration(minutes: 15),
        );
        async.elapse(const Duration(hours: 1));

        expect(checks, 0);
        expect(scheduler.isRunning, isFalse);

        scheduler.dispose();
        foreground.dispose();
      });
    });

    test('stops checking once disposed', () {
      fakeAsync((async) {
        var checks = 0;
        final foreground = _FakeForeground();
        final scheduler = AleraUpdateCheckScheduler(
          check: () async => checks++,
          foreground: foreground,
          interval: const Duration(minutes: 15),
        );
        async.flushMicrotasks();
        expect(checks, 1);

        scheduler.dispose();
        async.elapse(const Duration(hours: 3));
        expect(checks, 1);

        // A late foreground event after dispose must not restart the timer.
        foreground.emit(true);
        async.flushMicrotasks();
        expect(scheduler.isRunning, isFalse);
        expect(checks, 1);

        foreground.dispose();
      });
    });
  });
}
