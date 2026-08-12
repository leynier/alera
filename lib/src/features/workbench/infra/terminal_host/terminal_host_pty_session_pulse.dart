part of 'terminal_host_pty_session.dart';

mixin _TerminalPulsePtySessionSupport implements TerminalPulsePtySession {
  TerminalHostClient get _client;

  String get _sessionId;

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
    return client.terminalPulseStatus(_sessionId);
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
    return client.configureTerminalPulse(
      sessionId: _sessionId,
      configuration: configuration,
      armed: armed,
    );
  }
}
