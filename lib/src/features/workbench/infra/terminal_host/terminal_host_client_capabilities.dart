part of 'terminal_host_client.dart';

mixin _RuntimeHostCapabilitySupport
    implements TerminalHostClient, RuntimeHostCapabilityClient {
  _TerminalHostConnection? get _terminalConnection;
  _TerminalHostConnection? get _runtimeConnection;

  Future<_TerminalHostConnection> _connectRuntime();

  @override
  bool get supportsTerminalRestart =>
      _terminalConnection?.supportsTerminalRestart ??
      _runtimeConnection?.supportsTerminalRestart ??
      false;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    final connection = await _connectRuntime();
    return switch (capability) {
      aleraRuntimeHostRemoteAiDictationCapability =>
        connection.supportsRemoteAiDictation,
      _ => false,
    };
  }
}
