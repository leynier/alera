import 'dart:convert';
import 'dart:typed_data';

const int relayHelloVersion = 1;
const List<int> _fragmentMagic = <int>[0x41, 0x4c, 0x52, 0x46, 0x01];
const int _fragmentHeaderBytes = 13;
const int _relayFragmentPayloadBytes = 48 * 1024;
const int maxRelayEnvelopeBytes = 1024 * 1024;

class RelayFragmentReassembler {
  int? _total;
  BytesBuilder _bytes = BytesBuilder(copy: false);

  Uint8List? accept(List<int> payload) {
    if (!_startsWithFragmentMagic(payload)) {
      if (_total != null) {
        _reset();
        throw const FormatException('Relay fragment sequence was interrupted.');
      }
      return Uint8List.fromList(payload);
    }
    if (payload.length <= _fragmentHeaderBytes) {
      _reset();
      throw const FormatException('Relay fragment is truncated.');
    }
    final total = _readUint32(payload, 5);
    final offset = _readUint32(payload, 9);
    final chunk = payload.sublist(_fragmentHeaderBytes);
    if (total <= _relayFragmentPayloadBytes ||
        total > maxRelayEnvelopeBytes ||
        chunk.length > _relayFragmentPayloadBytes ||
        offset + chunk.length > total) {
      _reset();
      throw const FormatException(
        'Relay fragment is outside the supported range.',
      );
    }
    if (offset == 0) {
      _total = total;
      _bytes = BytesBuilder(copy: false);
    } else if (_total != total || offset != _bytes.length) {
      _reset();
      throw const FormatException('Relay fragment sequence is invalid.');
    }
    _bytes.add(chunk);
    if (_bytes.length != total) {
      return null;
    }
    final complete = _bytes.takeBytes();
    _reset();
    return complete;
  }

  void _reset() {
    _total = null;
    _bytes = BytesBuilder(copy: false);
  }
}

List<Uint8List> fragmentRelayPayload(List<int> payload) {
  if (payload.length > maxRelayEnvelopeBytes) {
    throw const FormatException('Relay envelope is too large.');
  }
  if (payload.length <= _relayFragmentPayloadBytes) {
    return <Uint8List>[Uint8List.fromList(payload)];
  }
  return <Uint8List>[
    for (
      var offset = 0;
      offset < payload.length;
      offset += _relayFragmentPayloadBytes
    )
      Uint8List.fromList(<int>[
        ..._fragmentMagic,
        ..._uint32(payload.length),
        ..._uint32(offset),
        ...payload.sublist(
          offset,
          offset + _relayFragmentPayloadBytes < payload.length
              ? offset + _relayFragmentPayloadBytes
              : payload.length,
        ),
      ]),
  ];
}

bool _startsWithFragmentMagic(List<int> payload) {
  if (payload.length < _fragmentMagic.length) return false;
  for (var index = 0; index < _fragmentMagic.length; index++) {
    if (payload[index] != _fragmentMagic[index]) return false;
  }
  return true;
}

List<int> _uint32(int value) => <int>[
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

int _readUint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

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
