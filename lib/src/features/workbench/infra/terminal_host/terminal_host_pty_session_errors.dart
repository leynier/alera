part of 'terminal_host_pty_session.dart';

extension _TerminalHostPtySessionErrors on TerminalHostPtySession {
  bool _shouldRecoverFromHostError(Object error) {
    final message = _hostErrorMessage(error);
    return message.contains('Terminal session is not attached') ||
        message.contains('Terminal host connection closed');
  }

  bool _isDefinitivelyNotAttached(Object error) {
    return _hostErrorMessage(
      error,
    ).contains('Terminal session is not attached');
  }

  String _hostErrorMessage(Object error) {
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }

  void _emitHostError(Object error) {
    if (!_disposed && !_events.isClosed && !_isInputBackpressure(error)) {
      _events.add(TerminalPtyErrorEvent(error));
    }
  }

  bool _isInputBackpressure(Object error) {
    return _hostErrorMessage(error).contains('terminal_input_backpressure');
  }
}
