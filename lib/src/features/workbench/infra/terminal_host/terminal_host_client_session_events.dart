part of 'terminal_host_client.dart';

/// Per-session event demultiplexing.
///
/// Every [TerminalHostPtySession] used to listen to the single global event
/// stream and discard everything addressed to another session, so one output
/// chunk cost a dispatch to every live terminal. Keeping one sink per session
/// makes that O(1).
mixin _TerminalHostClientSessionEvents {
  final Map<String, StreamController<TerminalHostEvent>> _sessionEvents =
      <String, StreamController<TerminalHostEvent>>{};

  bool _sessionEventsClosed = false;

  Stream<TerminalHostEvent> eventsForSession(String sessionId) {
    if (_sessionEventsClosed) {
      return const Stream<TerminalHostEvent>.empty();
    }
    return _sessionEvents
        .putIfAbsent(sessionId, StreamController<TerminalHostEvent>.broadcast)
        .stream;
  }

  void releaseSession(String sessionId) {
    final controller = _sessionEvents.remove(sessionId);
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }

  void _emitSessionEvent(String sessionId, TerminalHostEvent event) {
    final sink = _sessionEvents[sessionId];
    if (sink != null && !sink.isClosed) {
      sink.add(event);
    }
  }

  void _closeSessionEvents() {
    _sessionEventsClosed = true;
    for (final controller in _sessionEvents.values) {
      unawaited(controller.close());
    }
    _sessionEvents.clear();
  }
}
