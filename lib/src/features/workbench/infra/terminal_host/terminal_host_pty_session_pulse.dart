part of 'terminal_host_pty_session.dart';

mixin _TerminalPulsePtySessionSupport implements TerminalPulsePtySession {
  TerminalHostClient get _client;

  String get _sessionId;

  Future<T> _enqueueAttachmentOperation<T>(Future<T> Function() operation);

  Future<T> _withReattach<T>(
    Future<T> Function() operation, {
    required bool Function(Object error) shouldRecover,
  });

  @override
  bool get supportsTerminalPulse =>
      _client is TerminalPulseHostClient &&
      (_client as TerminalPulseHostClient).supportsTerminalPulse;

  @override
  Future<TerminalPulseState> terminalPulseStatus() {
    final client = _client is TerminalPulseHostClient
        ? _client as TerminalPulseHostClient
        : null;
    if (client == null || !client.supportsTerminalPulse) {
      throw UnsupportedError(
        'The running terminal host does not support Terminal Pulse.',
      );
    }
    return _enqueueAttachmentOperation(
      () => _withReattach(
        () => client.terminalPulseStatus(_sessionId),
        shouldRecover: _shouldRecoverFromTerminalHostError,
      ),
    );
  }

  @override
  Future<TerminalPulseState> configureTerminalPulse({
    required TerminalPulseConfiguration configuration,
    required bool armed,
  }) {
    final client = _client is TerminalPulseHostClient
        ? _client as TerminalPulseHostClient
        : null;
    if (client == null || !client.supportsTerminalPulse) {
      throw UnsupportedError(
        'The running terminal host does not support Terminal Pulse.',
      );
    }
    return _enqueueAttachmentOperation(
      () => _withReattach(
        () => client.configureTerminalPulse(
          sessionId: _sessionId,
          configuration: configuration,
          armed: armed,
        ),
        shouldRecover: _shouldRecoverFromTerminalHostError,
      ),
    );
  }
}
