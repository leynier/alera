import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';

/// Drives a recurring refresh that parks while the app window is hidden.
///
/// Recurring work whose result nobody can see should stop instead of burning
/// cycles: the timer runs only while the window is visible, hiding cancels
/// it, and returning refreshes immediately rather than waiting out a fresh
/// interval, mirroring the update check scheduler.
class ForegroundParkedRefresh({
  required AppForeground foreground,
  required final Duration interval,
  required final void Function() refresh,
}) {
  this {
    if (foreground.isForeground) {
      _arm();
    }
    _subscription = foreground.changes.listen((visible) {
      if (visible) {
        // Re-arm before refreshing: a refresh that rebuilds the owner
        // replaces this instance anyway, but an owner that only re-fetches
        // must not come back without its cadence.
        _arm();
        refresh();
      } else {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  late final StreamSubscription<bool> _subscription;
  Timer? _timer;

  void _arm() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription.cancel());
  }
}
