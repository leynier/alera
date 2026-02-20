import 'dart:convert';
import 'dart:typed_data';

class JsonRpcFramer {
  JsonRpcFramer();

  final List<int> _buffer = <int>[];

  List<Map<String, dynamic>> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);

    final messages = <Map<String, dynamic>>[];
    while (true) {
      final framed = _tryConsumeContentLengthMessage();
      if (framed != null) {
        messages.add(framed);
        continue;
      }

      if (_looksLikeContentLengthFrame()) {
        break;
      }

      final line = _tryConsumeJsonLineMessage();
      if (line != null) {
        messages.add(line);
        continue;
      }

      break;
    }

    return messages;
  }

  Map<String, dynamic>? _tryConsumeContentLengthMessage() {
    final headerEnd = _indexOfSequence(_buffer, <int>[13, 10, 13, 10]);
    if (headerEnd < 0) {
      return null;
    }

    final headerBytes = _buffer.sublist(0, headerEnd);
    final header = utf8.decode(headerBytes);
    final match = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false)
        .firstMatch(header);

    if (match == null) {
      return null;
    }

    final contentLength = int.parse(match.group(1)!);
    final bodyStart = headerEnd + 4;
    if (_buffer.length < bodyStart + contentLength) {
      return null;
    }

    final bodyBytes = _buffer.sublist(bodyStart, bodyStart + contentLength);
    _buffer.removeRange(0, bodyStart + contentLength);

    return _decodeJson(bodyBytes);
  }

  Map<String, dynamic>? _tryConsumeJsonLineMessage() {
    final newlineIndex = _buffer.indexOf(10);
    if (newlineIndex < 0) {
      return null;
    }

    final lineBytes = _buffer.sublist(0, newlineIndex);
    _buffer.removeRange(0, newlineIndex + 1);

    final trimmed = Uint8List.fromList(lineBytes)
        .where((value) => value != 13)
        .toList(growable: false);
    if (trimmed.isEmpty) {
      return null;
    }

    return _decodeJson(trimmed);
  }

  bool _looksLikeContentLengthFrame() {
    const prefix = 'Content-Length:';
    final length = prefix.length;
    if (_buffer.length < length) {
      return false;
    }

    final start = ascii.decode(_buffer.take(length).toList(growable: false));
    return start.toLowerCase() == prefix.toLowerCase();
  }

  Map<String, dynamic> _decodeJson(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('JSON-RPC payload must be an object');
    }
    return value;
  }

  int _indexOfSequence(List<int> source, List<int> pattern) {
    if (source.length < pattern.length) {
      return -1;
    }

    for (var i = 0; i <= source.length - pattern.length; i++) {
      var found = true;
      for (var j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          found = false;
          break;
        }
      }
      if (found) {
        return i;
      }
    }
    return -1;
  }
}
