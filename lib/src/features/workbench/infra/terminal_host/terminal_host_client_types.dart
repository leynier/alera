part of 'terminal_host_client.dart';

final class _TerminalHostConnection {
  /// Socket owned by this isolate. Used when the reader isolate could not be
  /// spawned, so a terminal never depends on the offload succeeding.
  _TerminalHostConnection(
    this._socket, {
    required this.supportsRuntime,
    required this.supportsOrchestration,
    required this.supportsTerminalRestart,
    required this.supportsDeferredInput,
    required this.supportsTerminalPulse,
    required this.supportsRemoteAiDictation,
  }) : _reader = null {
    _socketSub = _socket!.cast<List<int>>().listen(
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

  /// Socket owned by a reader isolate, which also does the framing and decodes
  /// terminal output, so nothing here touches raw bytes.
  _TerminalHostConnection.isolate(
    _TerminalHostSocketReader reader, {
    required this.supportsRuntime,
    required this.supportsOrchestration,
    required this.supportsTerminalRestart,
    required this.supportsDeferredInput,
    required this.supportsTerminalPulse,
    required this.supportsRemoteAiDictation,
  }) : _reader = reader,
       _socket = null {
    lines = reader.lines;
    outputFrames = const Stream<TerminalHostOutputFrame>.empty();
    decodedOutput = reader.output;
    unawaited(
      reader.done.then((_) {
        unawaited(_lines.close());
        unawaited(_output.close());
      }),
    );
  }

  final Socket? _socket;
  final _TerminalHostSocketReader? _reader;
  final bool supportsRuntime;
  final bool supportsOrchestration;
  final bool supportsTerminalRestart;
  final bool supportsDeferredInput;
  final bool supportsTerminalPulse;
  final bool supportsRemoteAiDictation;

  /// One reader for the whole connection. It starts newline-delimited so the
  /// handshake works against a host without the capability, and switches to
  /// length-prefixed frames once the hello response confirms the upgrade.
  final TerminalHostFrameReader _frameReader = TerminalHostFrameReader();
  final StreamController<Object?> _lines = StreamController<Object?>();
  final StreamController<TerminalHostOutputFrame> _output =
      StreamController<TerminalHostOutputFrame>();
  StreamSubscription<List<int>>? _socketSub;

  /// Control traffic: responses and events. Parsed already on the isolate
  /// path; a raw line on the fallback path, which has nowhere else to parse it.
  late final Stream<Object?> lines;

  /// PTY output as raw bytes. Empty on the isolate path, which delivers text.
  late final Stream<TerminalHostOutputFrame> outputFrames;

  /// PTY output already decoded off the UI isolate. Empty on the fallback path.
  Stream<TerminalHostOutputTextEvent> decodedOutput =
      const Stream<TerminalHostOutputTextEvent>.empty();

  void _consume(List<int> chunk) {
    for (final frame in _frameReader.add(chunk)) {
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

  final Completer<void> _authenticated = Completer<void>();
  bool _isClosed = false;

  Future<void> get authenticated => _authenticated.future;

  Future<void> get done => _reader?.done ?? _socket!.done;

  bool get isClosed => _isClosed;

  void completeAuthentication() {
    if (!_authenticated.isCompleted) {
      _authenticated.complete();
    }
  }

  void completeAuthenticationError(Object error) {
    if (!_authenticated.isCompleted) {
      _authenticated.completeError(error, StackTrace.current);
    }
  }

  void write(Map<String, Object?> message) {
    if (_isClosed) {
      throw StateError('Terminal host connection is closed.');
    }
    final reader = _reader;
    if (reader != null) {
      reader.write(utf8.encode('${jsonEncode(message)}\n'));
      return;
    }
    _socket!.writeln(jsonEncode(message));
  }

  void dispose() {
    _isClosed = true;
    unawaited(_socketSub?.cancel());
    _socketSub = null;
    unawaited(_lines.close());
    unawaited(_output.close());
    _reader?.dispose();
    _socket?.destroy();
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
    this.supportsTerminalRestart = false,
    this.supportsDeferredInput = false,
    this.supportsTerminalPulse = false,
    this.supportsRemoteAiDictation = false,
  });

  final int port;
  final String token;
  final bool supportsRuntime;
  final bool supportsOrchestration;
  final bool supportsBinaryFrames;
  final bool supportsTerminalRestart;
  final bool supportsDeferredInput;
  final bool supportsTerminalPulse;
  final bool supportsRemoteAiDictation;
}

final class _PendingHostRequest {
  const _PendingHostRequest(this.connection, this.completer);

  final _TerminalHostConnection connection;
  final Completer<Object?> completer;
}

final class _RuntimeMutationInProgressError extends StateError {
  _RuntimeMutationInProgressError() : super(_runtimeMutationInProgressMessage);
}

enum _HostConnectionRole { terminal, runtime }

const Duration _terminalHostConnectTimeout = Duration(seconds: 2);
const Duration _terminalHostRequestTimeout = Duration(seconds: 10);
const Duration _runtimeMutationRetryDelay = Duration(milliseconds: 50);
const String _runtimeMutationInProgressMessage =
    'A runtime mutation is in progress. Wait for it to finish and retry.';
const String _orchestrationHostRestartRequiredMessage =
    'The running terminal host does not support orchestration. Restart Alera to replace the terminal host before using orchestration.';
