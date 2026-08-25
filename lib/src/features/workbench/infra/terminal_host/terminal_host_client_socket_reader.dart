part of 'terminal_host_client.dart';

/// Main-isolate side of the socket reader.
///
/// Owns the ports, not the socket: the isolate owns that. Everything this class
/// hands back is already parsed, so the UI isolate does no framing and no
/// UTF-8 decoding of terminal output.
///
/// Spawning is allowed to fail. Losing terminals over an isolate problem would
/// be far worse than losing the offload, so the caller falls back to reading
/// the socket here instead.
final class _TerminalHostSocketReader {
  _TerminalHostSocketReader._(this._commands, this._fromIsolate);

  static Future<_TerminalHostSocketReader?> connect({
    required String host,
    required int port,
    required Duration connectTimeout,
  }) async {
    final fromIsolate = ReceivePort();
    final ready = Completer<SendPort?>();
    final reader = _TerminalHostSocketReader._(null, fromIsolate);
    reader._attach(fromIsolate, ready);
    final commands = await spawnTerminalHostSocketIsolate(
      host: host,
      port: port,
      toMain: fromIsolate.sendPort,
      connectTimeout: connectTimeout,
      awaitReady: () async {
        final port = await ready.future.timeout(
          connectTimeout,
          onTimeout: () => null,
        );
        if (port == null) {
          throw StateError('Terminal host socket isolate did not start.');
        }
        return port;
      },
    ).catchError((Object _) => null);
    if (commands == null) {
      fromIsolate.close();
      return null;
    }
    reader._commands = commands;
    return reader;
  }

  SendPort? _commands;
  final ReceivePort _fromIsolate;
  final StreamController<Object?> _lines =
      StreamController<Object?>.broadcast();
  final StreamController<TerminalHostOutputTextEvent> _output =
      StreamController<TerminalHostOutputTextEvent>.broadcast();
  final Completer<void> _done = Completer<void>();
  bool _closed = false;

  Stream<Object?> get lines => _lines.stream;
  Stream<TerminalHostOutputTextEvent> get output => _output.stream;
  Future<void> get done => _done.future;

  void _attach(ReceivePort port, Completer<SendPort?> ready) {
    port.listen((Object? message) {
      if (message is! List || message.isEmpty) {
        return;
      }
      switch (message[0]) {
        case terminalHostIsolateReady:
          if (!ready.isCompleted) {
            ready.complete(message[1] as SendPort);
          }
        case terminalHostIsolateLine:
          if (!_lines.isClosed) {
            _lines.add(message[1]);
          }
        case terminalHostIsolateOutput:
          if (!_output.isClosed) {
            _output.add(
              TerminalHostOutputTextEvent(
                message[1] as String,
                message[2] as String,
              ),
            );
          }
        case terminalHostIsolateError:
          if (!ready.isCompleted) {
            ready.complete(null);
          }
        case terminalHostIsolateClosed:
          _finish();
      }
    });
  }

  void write(List<int> bytes) {
    _commands?.send(<Object?>[terminalHostIsolateWrite, bytes]);
  }

  void dispose() {
    _commands?.send(const <Object?>[terminalHostIsolateClose]);
    _finish();
  }

  void _finish() {
    if (_closed) {
      return;
    }
    _closed = true;
    _commands = null;
    _fromIsolate.close();
    unawaited(_lines.close());
    unawaited(_output.close());
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

/// Opens a connection, preferring a reader isolate and falling back to reading
/// the socket on this isolate when spawning fails.
Future<_TerminalHostConnection> _openHostConnection(
  _TerminalHostControl control,
) async {
  final reader = await _TerminalHostSocketReader.connect(
    host: InternetAddress.loopbackIPv4.address,
    port: control.port,
    connectTimeout: _terminalHostConnectTimeout,
  );
  if (reader != null) {
    return _TerminalHostConnection.isolate(
      reader,
      supportsRuntime: control.supportsRuntime,
      supportsOrchestration: control.supportsOrchestration,
      supportsTerminalRestart: control.supportsTerminalRestart,
      supportsDeferredInput: control.supportsDeferredInput,
      supportsTerminalPulse: control.supportsTerminalPulse,
      supportsRemoteAiDictation: control.supportsRemoteAiDictation,
    );
  }
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    control.port,
    timeout: _terminalHostConnectTimeout,
  );
  return _TerminalHostConnection(
    socket,
    supportsRuntime: control.supportsRuntime,
    supportsOrchestration: control.supportsOrchestration,
    supportsTerminalRestart: control.supportsTerminalRestart,
    supportsDeferredInput: control.supportsDeferredInput,
    supportsTerminalPulse: control.supportsTerminalPulse,
    supportsRemoteAiDictation: control.supportsRemoteAiDictation,
  );
}
