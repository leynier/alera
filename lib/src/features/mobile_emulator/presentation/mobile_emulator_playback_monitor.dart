import 'dart:async';

enum MobileEmulatorPlaybackRecoveryAction { retry, fail }

class MobileEmulatorPlaybackRecoveryPolicy {
  MobileEmulatorPlaybackRecoveryPolicy({
    this.stabilityWindow = const Duration(seconds: 30),
  });

  final Duration stabilityWindow;
  Timer? _stabilityTimer;
  bool _automaticRetryUsed = false;

  void playbackStarted() {
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(stabilityWindow, reset);
  }

  MobileEmulatorPlaybackRecoveryAction recordFailure() {
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    if (_automaticRetryUsed) {
      return MobileEmulatorPlaybackRecoveryAction.fail;
    }
    _automaticRetryUsed = true;
    return MobileEmulatorPlaybackRecoveryAction.retry;
  }

  void reset() {
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    _automaticRetryUsed = false;
  }

  void dispose() => reset();
}

class MobileEmulatorPlaybackMonitor {
  MobileEmulatorPlaybackMonitor({
    required Stream<String> errors,
    required Stream<bool> completions,
    required this.onWarning,
    required this.onFailure,
    this.retryDelay = const Duration(milliseconds: 500),
  }) {
    _errorSubscription = errors.listen(_reportWarning);
    _completionSubscription = completions.listen((completed) {
      if (completed) {
        _scheduleFailure();
      }
    });
  }

  final void Function(String warning) onWarning;
  final void Function() onFailure;
  final Duration retryDelay;
  late final StreamSubscription<String> _errorSubscription;
  late final StreamSubscription<bool> _completionSubscription;
  Timer? _failureTimer;
  bool _warningReported = false;
  bool _disposed = false;

  void _reportWarning(String warning) {
    if (_disposed || _warningReported) {
      return;
    }
    _warningReported = true;
    onWarning(warning);
  }

  void _scheduleFailure() {
    if (_disposed || _failureTimer != null) {
      return;
    }
    _failureTimer = Timer(retryDelay, onFailure);
  }

  Future<void> dispose() async {
    _disposed = true;
    _failureTimer?.cancel();
    await Future.wait(<Future<void>>[
      _errorSubscription.cancel(),
      _completionSubscription.cancel(),
    ]);
  }
}
