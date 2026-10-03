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

/// Last line before the stream switches to frames.
///
/// The switch has to be visible in the bytes: the reader can live in another
/// isolate, so anything that flips it from outside races with the port
/// round-trip and mis-parses whatever arrived in between.
const String terminalHostBinaryFramesEnabledLine = 'binaryFramesEnabled';

sealed class const TerminalHostFrame();

final class const TerminalHostJsonFrame(final String json)
    extends TerminalHostFrame;

final class const TerminalHostOutputFrame(
  final String sessionId,
  final Uint8List data,
) extends TerminalHostFrame;

/// Incremental reader over a byte stream that may switch mid-connection.
///
/// The connection starts newline-delimited so the `hello` handshake works
/// against a host that does not support frames. Once the response confirms the
/// upgrade, [upgradeToBinary] is called and every later byte is framed. The
/// switch is driven from here, by the code that owns the bytes, so there is no
/// window where the mode is ambiguous.
class TerminalHostFrameReader {
  /// Unread bytes live in `_buffer[_start, _end)`. Frames are consumed by
  /// advancing `_start`, so taking one never shifts what follows it; the bytes
  /// are compacted only when an append needs the room.
  Uint8List _buffer = Uint8List(0);
  int _start = 0;
  int _end = 0;

  /// Where the newline search resumes, so a long line arriving in many chunks
  /// is scanned once rather than from its start on every chunk.
  int _lineScanFrom = 0;
  bool _binary = false;

  bool get isBinary => _binary;

  void upgradeToBinary() {
    _binary = true;
  }

  /// Appends [chunk] and returns whatever frames are now complete.
  List<TerminalHostFrame> add(List<int> chunk) {
    _append(chunk);
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
    _releaseIfDrained();
    return frames;
  }

  void _append(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }
    if (_buffer.length - _end < chunk.length) {
      final unread = _end - _start;
      final needed = unread + chunk.length;
      final target = needed <= _buffer.length
          ? _buffer
          : Uint8List(_grownCapacity(needed));
      target.setRange(0, unread, _buffer, _start);
      _lineScanFrom -= _start;
      _buffer = target;
      _start = 0;
      _end = unread;
    }
    _buffer.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }

  int _grownCapacity(int needed) {
    var capacity = _buffer.isEmpty ? _initialCapacity : _buffer.length;
    while (capacity < needed) {
      capacity *= 2;
    }
    return capacity;
  }

  /// A snapshot can grow the buffer to megabytes. Once it has been consumed,
  /// a large buffer is dropped rather than held for the life of the socket.
  void _releaseIfDrained() {
    if (_start != _end) {
      return;
    }
    _start = 0;
    _end = 0;
    _lineScanFrom = 0;
    if (_buffer.length > _retainedCapacity) {
      _buffer = Uint8List(0);
    }
  }

  TerminalHostFrame? _takeLine() {
    var newline = -1;
    for (
      var index = _lineScanFrom < _start ? _start : _lineScanFrom;
      index < _end;
      index += 1
    ) {
      if (_buffer[index] == 0x0a) {
        newline = index;
        break;
      }
    }
    if (newline < 0) {
      _lineScanFrom = _end;
      return null;
    }
    final line = utf8.decode(
      Uint8List.sublistView(_buffer, _start, newline),
      allowMalformed: true,
    );
    _start = newline + 1;
    _lineScanFrom = _start;
    if (line.contains(terminalHostBinaryFramesEnabledLine)) {
      _binary = true;
    }
    return TerminalHostJsonFrame(line);
  }

  TerminalHostFrame? _takeBinaryFrame() {
    if (_end - _start < terminalHostFrameHeaderLength) {
      return null;
    }
    final kind = _buffer[_start];
    final length =
        (_buffer[_start + 1] << 24) |
        (_buffer[_start + 2] << 16) |
        (_buffer[_start + 3] << 8) |
        _buffer[_start + 4];
    final payloadStart = _start + terminalHostFrameHeaderLength;
    final end = payloadStart + length;
    if (_end < end) {
      return null;
    }
    _start = end;
    _lineScanFrom = end;
    switch (kind) {
      case terminalHostFrameKindJson:
        return TerminalHostJsonFrame(
          utf8.decode(
            Uint8List.sublistView(_buffer, payloadStart, end),
            allowMalformed: true,
          ),
        );
      case terminalHostFrameKindOutput:
        return _decodeOutputFrame(payloadStart, end);
      default:
        // Unknown kinds are skipped rather than fatal: the length prefix keeps
        // the stream parseable, so a newer host adding a frame type must not
        // break an older client.
        return null;
    }
  }

  TerminalHostFrame? _decodeOutputFrame(int payloadStart, int end) {
    if (end - payloadStart < 2) {
      return null;
    }
    final idLength = (_buffer[payloadStart] << 8) | _buffer[payloadStart + 1];
    final idEnd = payloadStart + 2 + idLength;
    if (end < idEnd) {
      return null;
    }
    final sessionId = utf8.decode(
      Uint8List.sublistView(_buffer, payloadStart + 2, idEnd),
      allowMalformed: true,
    );
    // The one copy: the frame outlives this buffer, which is reused.
    return TerminalHostOutputFrame(sessionId, _buffer.sublist(idEnd, end));
  }
}

const int _initialCapacity = 64 * 1024;

/// Largest buffer kept once drained; a typical PTY read fits several times.
const int _retainedCapacity = 256 * 1024;

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
