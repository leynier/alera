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
MobileTerminalOutputEvent? decodeMobileBinaryOutput(List<int> raw) {
  if (raw.length < 2) {
    return null;
  }
  final idLength = (raw[0] << 8) | raw[1];
  final idEnd = 2 + idLength;
  if (raw.length < idEnd) {
    return null;
  }
  final sessionId = utf8.decode(raw.sublist(2, idEnd), allowMalformed: true);
  if (sessionId.isEmpty) {
    return null;
  }
  return MobileTerminalOutputEvent(
    sessionId,
    Uint8List.fromList(raw.sublist(idEnd)),
  );
}
