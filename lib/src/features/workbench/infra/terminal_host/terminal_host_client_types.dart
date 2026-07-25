part of 'terminal_host_client.dart';

final class _TerminalHostConnection {
  _TerminalHostConnection(
    this._socket, {
    required this.supportsRuntime,
    required this.supportsOrchestration,
  }) {
    _socketSub = _socket.cast<List<int>>().listen(
      _consume,
      onError: _lines.addError,
      onDone: () {
        unawaited(_lines.close());
        unawaited(_output.close());
      },
    );
    lines = _lines.stream.asBroadcastStream();
    outputFrames = _output.stream.asBroadcastStream();
  }

  final Socket _socket;
  final bool supportsRuntime;
  final bool supportsOrchestration;

  /// One reader for the whole connection. It starts newline-delimited so the
  /// handshake works against a host without the capability, and switches to
  /// length-prefixed frames once the hello response confirms the upgrade.
  final TerminalHostFrameReader _reader = TerminalHostFrameReader();
  final StreamController<String> _lines = StreamController<String>();
  final StreamController<TerminalHostOutputFrame> _output =
      StreamController<TerminalHostOutputFrame>();
  StreamSubscription<List<int>>? _socketSub;

  /// Control traffic: responses and events, still JSON.
  late final Stream<String> lines;

  /// PTY output, delivered as raw bytes with no base64 or JSON in the way.
  late final Stream<TerminalHostOutputFrame> outputFrames;

  void _consume(List<int> chunk) {
    for (final frame in _reader.add(chunk)) {
      switch (frame) {
        case TerminalHostJsonFrame(:final json):
          if (!_lines.isClosed) {
            _lines.add(json);
          }
        case TerminalHostOutputFrame():
          if (!_output.isClosed) {
            _output.add(frame);
          }
      }
    }
  }

  /// Switches the reader after the hello response has been consumed. The host
  /// queues its upgrade marker behind that response on the same lane, so every
  /// byte from here on is framed.
  void upgradeToBinaryFrames() => _reader.upgradeToBinary();
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
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    unawaited(_lines.close());
    unawaited(_output.close());
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
    this.supportsBinaryFrames = false,
  });

  final int port;
  final String token;
  final bool supportsRuntime;
  final bool supportsOrchestration;
  final bool supportsBinaryFrames;
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
