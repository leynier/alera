part of 'terminal_host_pty_session.dart';

/// One pending host write. Plain keystroke bytes stay open so later input can
/// join them; a deferred enter keeps its own request, in order.
final class _QueuedTerminalInput {
  _QueuedTerminalInput.bytes(List<int> bytes)
    : builder = BytesBuilder()..add(bytes),
      send = null;

  _QueuedTerminalInput.operation(Future<void> Function() this.send)
    : builder = null;

  final BytesBuilder? builder;
  final Future<void> Function()? send;
}

/// Sends terminal input one host request at a time, merging the bytes that
/// arrive while a request is in flight.
///
/// A wheel tick over a TUI reports up to ten mouse events, and a fast scroll
/// or paste produces many more. Sent one request each, every report paid its
/// own JSON, base64, completer and actor turn on the host, and the host input
/// queue could reject the burst. The first byte still leaves at once; only the
/// input that arrives behind it waits, for at most one round trip.
mixin _TerminalHostInputQueue {
  final Queue<_QueuedTerminalInput> _inputQueue = Queue<_QueuedTerminalInput>();
  bool _drainingInput = false;

  bool get _disposed;

  Future<void> _writeBytes(List<int> bytes);

  void _reportInputError(Object error);

  void _queueInputBytes(List<int> bytes) {
    final last = _inputQueue.isEmpty ? null : _inputQueue.last;
    if (last?.builder case final builder?) {
      builder.add(bytes);
    } else {
      _inputQueue.add(_QueuedTerminalInput.bytes(bytes));
    }
    _drainInputQueue();
  }

  /// Queues [send] behind any earlier input and reports its errors through
  /// the session's error events.
  void _queueInputOperation(Future<void> Function() send) {
    _inputQueue.add(_QueuedTerminalInput.operation(send));
    _drainInputQueue();
  }

  void _drainInputQueue() {
    if (_drainingInput) {
      return;
    }
    _drainingInput = true;
    unawaited(_runInputQueue());
  }

  Future<void> _runInputQueue() async {
    try {
      while (_inputQueue.isNotEmpty && !_disposed) {
        final next = _inputQueue.removeFirst();
        try {
          if (next.builder case final builder?) {
            await _writeBytes(builder.takeBytes());
          } else {
            await next.send!();
          }
        } catch (error) {
          _reportInputError(error);
        }
      }
      if (_disposed) {
        _inputQueue.clear();
      }
    } finally {
      _drainingInput = false;
    }
  }
}
