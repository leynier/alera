part of 'terminal_host_client.dart';

mixin _RuntimeHostCapabilitySupport on SocketTerminalHostClient {
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
