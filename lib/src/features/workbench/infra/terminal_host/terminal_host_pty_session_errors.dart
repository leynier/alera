part of 'terminal_host_pty_session.dart';

bool _shouldRecoverFromTerminalHostError(Object error) {
  final message = _terminalHostErrorMessage(error);
  return message.contains('Terminal session is not attached') ||
      message.contains('Terminal host connection closed');
}

String _terminalHostErrorMessage(Object error) {
  if (error is StateError) {
    return error.message;
  }
  return error.toString();
}

extension _TerminalHostPtySessionErrors on TerminalHostPtySession {
  bool _shouldRecoverFromHostError(Object error) {
    return _shouldRecoverFromTerminalHostError(error);
  }

  bool _isDefinitivelyNotAttached(Object error) {
    return _terminalHostErrorMessage(error)
        .contains('Terminal session is not attached');
  }

  void _emitHostError(Object error) {
    if (!_disposed && !_events.isClosed && !_isInputBackpressure(error)) {
      _events.add(TerminalPtyErrorEvent(error));
    }
  }

  bool _isInputBackpressure(Object error) {
    return _terminalHostErrorMessage(error)
        .contains('terminal_input_backpressure');
  }
}
