part of 'terminal_host_client.dart';

const Duration _terminalPulseSetupTimeout = Duration(seconds: 30);

mixin _TerminalPulseHostClientSupport implements TerminalPulseHostClient {
  _TerminalHostConnection? get _terminalConnection;

  _TerminalHostConnection? get _runtimeConnection;

  Future<Map<String, Object?>> _terminalRequestMap(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  });

  bool get supportsDeferredInput =>
      _terminalConnection?.supportsDeferredInput ??
      _runtimeConnection?.supportsDeferredInput ??
      false;

  @override
  bool get supportsTerminalPulse =>
      _terminalConnection?.supportsTerminalPulse ??
      _runtimeConnection?.supportsTerminalPulse ??
      false;

  @override
  Future<TerminalPulseState> terminalPulseStatus(String sessionId) async {
    if (!supportsTerminalPulse) {
      throw UnsupportedError(
        'The running terminal host does not support Terminal Pulse.',
      );
    }
    return TerminalPulseState.fromJson(
      await _terminalRequestMap('terminal.pulse.status', <String, Object?>{
        'sessionId': sessionId,
      }),
    );
  }

  @override
  Future<TerminalPulseState> configureTerminalPulse({
    required String sessionId,
    required TerminalPulseConfiguration configuration,
    required bool armed,
  }) async {
    if (!supportsTerminalPulse) {
      throw UnsupportedError(
        'The running terminal host does not support Terminal Pulse.',
      );
    }
    return TerminalPulseState.fromJson(
      await _terminalRequestMap('terminal.pulse.configure', <String, Object?>{
        'sessionId': sessionId,
        'configuration': configuration.toJson(),
        'armed': armed,
      }, timeout: _terminalPulseSetupTimeout),
    );
  }
}
