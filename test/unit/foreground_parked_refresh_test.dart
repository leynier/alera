import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/app_window/domain/foreground_parked_refresh.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// The resource monitor and runtime host status providers refresh through
/// this. These cases pin that the cadence stops while the window is hidden
/// and that returning refreshes immediately instead of waiting out a fresh
/// interval.
void main() {
  const interval = Duration(seconds: 15);

  group('ForegroundParkedRefresh', () {
    test('refreshes on the cadence while the window is visible', () {
      fakeAsync((async) {
        final foreground = _FakeAppForeground();
        var refreshes = 0;
        final refresh = ForegroundParkedRefresh(
          foreground: foreground,
          interval: interval,
          refresh: () => refreshes++,
        );

        async.elapse(interval * 3);

        expect(refreshes, 3);
        refresh.dispose();
        foreground.dispose();
      });
    });

    test('never starts the cadence while hidden', () {
      fakeAsync((async) {
        final foreground = _FakeAppForeground(false);
        var refreshes = 0;
        final refresh = ForegroundParkedRefresh(
          foreground: foreground,
          interval: interval,
          refresh: () => refreshes++,
        );

        async.elapse(interval * 10);

        expect(refreshes, 0);
        refresh.dispose();
        foreground.dispose();
      });
    });

    test('parks when the window hides and stays silent', () {
      fakeAsync((async) {
        final foreground = _FakeAppForeground();
        var refreshes = 0;
        final refresh = ForegroundParkedRefresh(
          foreground: foreground,
          interval: interval,
          refresh: () => refreshes++,
        );

        async.elapse(interval);
        expect(refreshes, 1);

        foreground.setForeground(false);
        async.elapse(interval * 10);

        expect(refreshes, 1);
        refresh.dispose();
        foreground.dispose();
      });
    });

    test('refreshes immediately on return and re-arms the cadence', () {
      fakeAsync((async) {
        final foreground = _FakeAppForeground(false);
        var refreshes = 0;
        final refresh = ForegroundParkedRefresh(
          foreground: foreground,
          interval: interval,
          refresh: () => refreshes++,
        );

        foreground.setForeground(true);
        async.flushMicrotasks();
        expect(refreshes, 1);

        async.elapse(interval);
        expect(refreshes, 2);
        refresh.dispose();
        foreground.dispose();
      });
    });

    test('dispose stops the cadence and the foreground watch', () {
      fakeAsync((async) {
        final foreground = _FakeAppForeground();
        var refreshes = 0;
        ForegroundParkedRefresh(
          foreground: foreground,
          interval: interval,
          refresh: () => refreshes++,
        ).dispose();

        async.elapse(interval * 3);
        foreground.setForeground(false);
        foreground.setForeground(true);
        async.flushMicrotasks();

        expect(refreshes, 0);
        foreground.dispose();
      });
    });
  });
}

class _FakeAppForeground implements AppForeground {
  _FakeAppForeground([this._isForeground = true]);

  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );
  bool _isForeground;

  @override
  bool get isForeground => _isForeground;

  @override
  Stream<bool> get changes => _changes.stream;

  void setForeground(bool value) {
    if (_isForeground == value) {
      return;
    }
    _isForeground = value;
    _changes.add(value);
  }

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}
