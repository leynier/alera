part of 'terminal_host_client.dart';

final class _TerminalHostConnection {
  _TerminalHostConnection(
    this._socket, {
    required this.supportsRuntime,
    required this.supportsOrchestration,
  }) : lines = _socket
           .cast<List<int>>()
           .transform(utf8.decoder)
           .transform(const LineSplitter())
           .asBroadcastStream();

  final Socket _socket;
  final bool supportsRuntime;
  final bool supportsOrchestration;
  final Stream<String> lines;
  final Completer<void> _authenticated = Completer<void>();
  bool _isClosed = false;

  Future<void> get authenticated => _authenticated.future;

  Future<void> get done => _socket.done;

  bool get isClosed => _isClosed;

  void completeAuthentication() {
    if (!_authenticated.isCompleted) {
      _authenticated.complete();
    }
  }

  void completeAuthenticationError(Object error) {
    if (!_authenticated.isCompleted) {
      _authenticated.completeError(error);
    }
  }

  void write(Map<String, Object?> message) {
    if (_isClosed) {
      throw StateError('Terminal host connection is closed.');
    }
    _socket.writeln(jsonEncode(message));
  }

  void dispose() {
    _isClosed = true;
    _socket.destroy();
  }
}

final class _TerminalHostPaths {
  const _TerminalHostPaths({
    required this.runtimeDir,
    required this.controlFile,
    required this.runtimeControlFile,
  });

  final Directory runtimeDir;
  final File controlFile;
  final File runtimeControlFile;
}

final class _TerminalHostControl {
  const _TerminalHostControl({
    required this.port,
    required this.token,
    required this.supportsRuntime,
    required this.supportsOrchestration,
  });

  final int port;
  final String token;
  final bool supportsRuntime;
  final bool supportsOrchestration;
}

final class _PendingHostRequest {
  const _PendingHostRequest(this.connection, this.completer);

  final _TerminalHostConnection connection;
  final Completer<Object?> completer;
}

enum _HostConnectionRole { terminal, runtime }

const Duration _terminalHostConnectTimeout = Duration(seconds: 2);
const Duration _terminalHostRequestTimeout = Duration(seconds: 10);
const String _orchestrationHostRestartRequiredMessage =
    'The running terminal host does not support orchestration. Restart Alera to replace the terminal host before using orchestration.';
