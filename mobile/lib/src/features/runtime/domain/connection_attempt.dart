import 'dart:async';

/// One deadline and cancellation scope across discovery, HTTP and WebSocket setup.
class ConnectionAttempt({Duration timeout = const Duration(seconds: 30)}) {
  this {
    _timer = Timer(timeout, cancel);
  }

  static final Object _zoneKey = Object();
  static ConnectionAttempt? get current =>
      Zone.current[_zoneKey] as ConnectionAttempt?;
  final Completer<void> _cancelled = Completer<void>();
  late final Timer _timer;
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;

  void check() {
    if (isCancelled) throw TimeoutException('Connection attempt ended.');
  }

  Future<T> wait<T>(Future<T> operation) {
    check();
    return Future.any([
      operation,
      cancelled.then<T>(
        (_) => throw TimeoutException('Connection attempt ended.'),
      ),
    ]);
  }

  Future<T> run<T>(Future<T> Function() action) => runZoned(
    () => wait(Future<T>.sync(action)),
    zoneValues: {_zoneKey: this},
  );

  void cancel() {
    _timer.cancel();
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void finish() => _timer.cancel();
}
