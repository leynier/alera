part of 'terminal_host_client.dart';

mixin _RuntimeHostCapabilitySupport
    implements TerminalHostClient, RuntimeHostCapabilityClient {
  bool get _disposed;

  void _throwIfAppQuitInProgress();

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
    if (_disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    _throwIfAppQuitInProgress();
    final connection = await _connectRuntime();
    return switch (capability) {
      aleraRuntimeHostRemoteAiDictationCapability =>
        connection.supportsRemoteAiDictation,
      aleraRuntimeHostWorkspaceSectionsCapability =>
        connection.supportsWorkspaceSections,
      _ => false,
    };
  }
}
