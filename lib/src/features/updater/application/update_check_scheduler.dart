import 'dart:async';

import 'package:alera/src/features/app_window/domain/app_foreground.dart';

/// How often a visible window re-checks for a new release.
const Duration aleraUpdateCheckInterval = Duration(minutes: 15);

/// Drives a recurring update check while the window is visible.
///
/// The timer parks whenever the window is hidden: a minimised app cannot show
/// the result, and on Linux every wake still costs a composited frame. Coming
/// back checks immediately rather than waiting out the remainder of an interval
/// the user could not see.
class AleraUpdateCheckScheduler({
  required final Future<void> Function() check,
  required final AppForeground foreground,
  this.interval = aleraUpdateCheckInterval,
}) {
  this {
    _foregroundChanges = foreground.changes.listen(_applyForeground);
    if (foreground.isForeground) {
      _start();
    }
  }

  /// Overridable so tests drive the cadence without real waits.
  final Duration interval;

  Timer? _timer;
  StreamSubscription<bool>? _foregroundChanges;
  var _disposed = false;

  bool get isRunning => _timer != null;

  void dispose() {
    _disposed = true;
    _stop();
    unawaited(_foregroundChanges?.cancel());
    _foregroundChanges = null;
  }

  void _applyForeground(bool isForeground) {
    if (_disposed) {
      return;
    }
    if (isForeground) {
      _start();
      return;
    }
    _stop();
  }

  void _start() {
    if (_disposed || _timer != null) {
      return;
    }
    _timer = Timer.periodic(interval, (_) => _runCheck());
    // A window that has been hidden for longer than the interval is exactly the
    // case where a release is most likely to be waiting, so do not make the
    // user wait out a fresh interval before finding out.
    _runCheck();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _runCheck() {
    if (_disposed) {
      return;
    }
    // Deferred because the first check runs while this object is being built by
    // its provider, and Riverpod forbids a provider from writing to another one
    // during its own initialization. The controller already ignores a call
    // while a check is in flight, so a slow check cannot stack up behind the
    // timer either.
    scheduleMicrotask(() {
      if (_disposed) {
        return;
      }
      unawaited(check());
    });
  }
}
