/// Length-prefixed framing for the local terminal-host socket.
///
/// Mirrors `rust/alera-cli/src/terminal_host/frame_codec.rs`. Deliberately free
/// of Flutter imports so it can also run inside a plain isolate.
///
/// ```text
/// [u8 kind][u32be length][payload]
///
/// kind 1 = JSON     payload = the same object that would have been a line
/// kind 2 = output   payload = [u16be len][sessionId utf8][raw pty bytes]
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

const int terminalHostFrameKindJson = 1;
const int terminalHostFrameKindOutput = 2;

/// Kind byte plus the u32 length.
const int terminalHostFrameHeaderLength = 5;

sealed class TerminalHostFrame {
  const TerminalHostFrame();
}

final class TerminalHostJsonFrame extends TerminalHostFrame {
  const TerminalHostJsonFrame(this.json);

  final String json;
}

final class TerminalHostOutputFrame extends TerminalHostFrame {
  const TerminalHostOutputFrame(this.sessionId, this.data);

  final String sessionId;
  final Uint8List data;
}

/// Incremental reader over a byte stream that may switch mid-connection.
///
/// The connection starts newline-delimited so the `hello` handshake works
/// against a host that does not support frames. Once the response confirms the
/// upgrade, [upgradeToBinary] is called and every later byte is framed. The
/// switch is driven from here, by the code that owns the bytes, so there is no
/// window where the mode is ambiguous.
class TerminalHostFrameReader {
  final List<int> _buffer = <int>[];
  bool _binary = false;

  bool get isBinary => _binary;

  void upgradeToBinary() {
    _binary = true;
  }

  /// Appends [chunk] and returns whatever frames are now complete.
  List<TerminalHostFrame> add(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <TerminalHostFrame>[];
    while (true) {
      final frame = _binary ? _takeBinaryFrame() : _takeLine();
      if (frame == null) {
        break;
      }
      frames.add(frame);
      // The upgrade lands between frames, so re-check the mode every pass
      // rather than deciding once per chunk.
    }
    return frames;
  }

  TerminalHostFrame? _takeLine() {
    final newline = _buffer.indexOf(0x0a);
    if (newline < 0) {
      return null;
    }
    final line = utf8.decode(_buffer.sublist(0, newline), allowMalformed: true);
    _buffer.removeRange(0, newline + 1);
    return TerminalHostJsonFrame(line);
  }

  TerminalHostFrame? _takeBinaryFrame() {
    if (_buffer.length < terminalHostFrameHeaderLength) {
      return null;
    }
    final kind = _buffer[0];
    final length =
        (_buffer[1] << 24) |
        (_buffer[2] << 16) |
        (_buffer[3] << 8) |
        _buffer[4];
    final end = terminalHostFrameHeaderLength + length;
    if (_buffer.length < end) {
      return null;
    }
    final payload = Uint8List.fromList(
      _buffer.sublist(terminalHostFrameHeaderLength, end),
    );
    _buffer.removeRange(0, end);
    switch (kind) {
      case terminalHostFrameKindJson:
        return TerminalHostJsonFrame(
          utf8.decode(payload, allowMalformed: true),
        );
      case terminalHostFrameKindOutput:
        return _decodeOutputFrame(payload);
      default:
        // Unknown kinds are skipped rather than fatal: the length prefix keeps
        // the stream parseable, so a newer host adding a frame type must not
        // break an older client.
        return null;
    }
  }

  TerminalHostFrame? _decodeOutputFrame(Uint8List payload) {
    if (payload.length < 2) {
      return null;
    }
    final idLength = (payload[0] << 8) | payload[1];
    final idEnd = 2 + idLength;
    if (payload.length < idEnd) {
      return null;
    }
    final sessionId = utf8.decode(
      payload.sublist(2, idEnd),
      allowMalformed: true,
    );
    return TerminalHostOutputFrame(sessionId, payload.sublist(idEnd));
  }
}

/// Encodes a JSON frame, used by tests and by any writer that speaks frames.
Uint8List encodeTerminalHostJsonFrame(String json) {
  final payload = utf8.encode(json);
  return _frame(terminalHostFrameKindJson, payload);
}

Uint8List encodeTerminalHostOutputFrame(String sessionId, List<int> data) {
  final id = utf8.encode(sessionId);
  final payload = Uint8List(2 + id.length + data.length)
    ..[0] = (id.length >> 8) & 0xff
    ..[1] = id.length & 0xff
    ..setRange(2, 2 + id.length, id)
    ..setRange(2 + id.length, 2 + id.length + data.length, data);
  return _frame(terminalHostFrameKindOutput, payload);
}

Uint8List _frame(int kind, List<int> payload) {
  final out = Uint8List(terminalHostFrameHeaderLength + payload.length)
    ..[0] = kind
    ..[1] = (payload.length >> 24) & 0xff
    ..[2] = (payload.length >> 16) & 0xff
    ..[3] = (payload.length >> 8) & 0xff
    ..[4] = payload.length & 0xff
    ..setRange(
      terminalHostFrameHeaderLength,
      terminalHostFrameHeaderLength + payload.length,
      payload,
    );
  return out;
}
