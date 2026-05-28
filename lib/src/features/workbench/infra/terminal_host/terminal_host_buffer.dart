part of 'terminal_host_server.dart';

final class _TerminalHostByteBuffer {
  _TerminalHostByteBuffer(
    this._maxBytes, [
    List<int> initialBuffer = const <int>[],
  ]) {
    if (initialBuffer.isNotEmpty) {
      append(Uint8List.fromList(initialBuffer));
    }
  }

  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  int _length = 0;
  int _maxBytes;

  set maxBytes(int value) {
    _maxBytes = value;
    _trimToLimit();
  }

  void append(Uint8List data) {
    if (data.isEmpty) {
      return;
    }
    if (data.length >= _maxBytes) {
      _chunks.clear();
      _chunks.add(Uint8List.fromList(data.sublist(data.length - _maxBytes)));
      _length = _maxBytes;
      return;
    }
    _chunks.add(Uint8List.fromList(data));
    _length += data.length;
    _trimToLimit();
  }

  String toBase64() {
    return encodeTerminalHostBytes(toBytes());
  }

  Uint8List toBytes() {
    final output = Uint8List(_length);
    var offset = 0;
    for (final chunk in _chunks) {
      output.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return output;
  }

  void _trimToLimit() {
    var excess = _length - _maxBytes;
    while (excess > 0 && _chunks.isNotEmpty) {
      final first = _chunks.removeFirst();
      if (first.length <= excess) {
        _length -= first.length;
        excess -= first.length;
        continue;
      }
      final remaining = Uint8List.fromList(first.sublist(excess));
      _chunks.addFirst(remaining);
      _length -= excess;
      excess = 0;
    }
  }
}

final class _TerminalHostClientConnection {
  _TerminalHostClientConnection(this._socket, {required this.onDispose})
    : lines = _socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();

  final Socket _socket;
  final void Function(_TerminalHostClientConnection client) onDispose;
  final Stream<String> lines;
  bool authenticated = false;
  bool _disposed = false;

  void requireAuthenticated() {
    if (!authenticated) {
      throw StateError('Terminal host client is not authenticated.');
    }
  }

  void write(Map<String, Object?> message) {
    if (_disposed) {
      return;
    }
    _socket.writeln(jsonEncode(message));
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    onDispose(this);
    _socket.destroy();
  }
}

void _terminalHostPtyReader(List<Object?> args) {
  final pty = args[0] as PortablePty;
  final sendPort = args[1] as SendPort;
  try {
    while (true) {
      final data = pty.readSync(_terminalHostReadChunkBytes);
      if (data.isEmpty) {
        break;
      }
      sendPort.send(data);
    }
    sendPort.send(<Object?, Object?>{'type': 'exit', 'exitCode': pty.wait()});
  } catch (error) {
    // coverage:ignore-start
    int exitCode = -1;
    try {
      exitCode = pty.tryWait() ?? -1;
    } catch (_) {}
    sendPort.send(<Object?, Object?>{
      'type': 'error',
      'error': error.toString(),
      'exitCode': exitCode,
    });
    // coverage:ignore-end
  }
}

const int _terminalHostReadChunkBytes = 8192;
const Duration _terminalHostCheckpointDelay = Duration(seconds: 5);
