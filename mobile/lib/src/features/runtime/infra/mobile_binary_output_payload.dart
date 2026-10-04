import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

/// Decodes `[u16be idLength][sessionId][raw bytes]`.
///
/// The same payload the desktop socket carries inside a length-prefixed frame,
/// minus the length prefix: the WebSocket already delimits messages.
///
/// Returns null for anything malformed rather than throwing. A bad message
/// must not take down the output stream for a session that is otherwise fine.
///
/// The output is a view into the message rather than a copy. Each message is
/// its own allocation that nothing reuses, and copying it twice per chunk was
/// pure overhead on the busiest path a terminal has.
MobileTerminalOutputEvent? decodeMobileBinaryOutput(List<int> raw) {
  if (raw.length < 2) {
    return null;
  }
  final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
  final idLength = (bytes[0] << 8) | bytes[1];
  final idEnd = 2 + idLength;
  if (bytes.length < idEnd) {
    return null;
  }
  final sessionId = utf8.decode(
    Uint8List.sublistView(bytes, 2, idEnd),
    allowMalformed: true,
  );
  if (sessionId.isEmpty) {
    return null;
  }
  return MobileTerminalOutputEvent(
    sessionId,
    Uint8List.sublistView(bytes, idEnd),
  );
}

bool looksLikeJsonBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d) {
      continue;
    }
    return byte == 0x7b || byte == 0x5b;
  }
  return false;
}
