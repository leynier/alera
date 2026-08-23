import 'dart:convert';
import 'dart:typed_data';

const int relayHelloVersion = 1;

Uint8List wrapRelayFrame(String clientId, List<int> payload) {
  final id = utf8.encode(clientId);
  if (id.isEmpty || id.length > 128) {
    throw const FormatException('Relay client ID is invalid.');
  }
  return Uint8List.fromList(<int>[
    (id.length >> 8) & 0xff,
    id.length & 0xff,
    ...id,
    ...payload,
  ]);
}

(String, Uint8List) unwrapRelayFrame(List<int> frame) {
  if (frame.length < 2) {
    throw const FormatException('Relay frame is truncated.');
  }
  final idLength = (frame[0] << 8) | frame[1];
  if (idLength == 0 || idLength > 128 || frame.length < idLength + 2) {
    throw const FormatException('Relay client ID is invalid.');
  }
  final clientId = utf8.decode(frame.sublist(2, idLength + 2));
  return (clientId, Uint8List.fromList(frame.sublist(idLength + 2)));
}

Map<String, Object?> decodeRelayJson(List<int> bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map) {
    throw const FormatException('Relay handshake payload is not an object.');
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Uint8List encodeRelayJson(Map<String, Object?> value) {
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}
