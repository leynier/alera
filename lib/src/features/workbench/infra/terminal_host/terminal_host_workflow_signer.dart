part of 'terminal_host_client.dart';

mixin _WorkflowDecisionSignerSupport implements WorkflowDecisionSigner {
  Future<_TerminalHostPaths> _runtimePaths();
  bool get _disposed;

  @override
  Future<Uint8List> sign(String statementJson) async {
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    // Resolve the same runtime directory as this client's connection, including
    // injected development profiles. Never use another profile's credential.
    final paths = await _runtimePaths();
    if (_disposed) {
      throw const TerminalHostConnectionClosedException();
    }
    return NativeWorkflowDecisionSigner(paths.runtimeDir.path)
        .sign(statementJson);
  }
}
