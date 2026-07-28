import 'dart:async';

class MobileEmulatorPlaybackMonitor {
  MobileEmulatorPlaybackMonitor({
    required Stream<String> errors,
    required Stream<bool> completions,
    required this.onFailure,
    this.retryDelay = const Duration(milliseconds: 500),
  }) {
    _errorSubscription = errors.listen((_) => _scheduleFailure());
    _completionSubscription = completions.listen((completed) {
      if (completed) {
        _scheduleFailure();
      }
    });
  }

  final void Function() onFailure;
  final Duration retryDelay;
  late final StreamSubscription<String> _errorSubscription;
  late final StreamSubscription<bool> _completionSubscription;
  Timer? _failureTimer;
  bool _disposed = false;

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
