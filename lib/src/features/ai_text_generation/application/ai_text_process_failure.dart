import 'dart:convert';

const int _maxAiTextFailureDetailLength = 1000;

String? aiTextProcessFailureDetail(String stdout, String stderr) {
  final combined = '$stdout\n$stderr'
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .trim();
  if (combined.isEmpty) {
    return null;
  }
  final lines = combined
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  for (final line in lines.reversed) {
    try {
      final message = _messageFromJson(jsonDecode(line));
      if (message != null) {
        return _capFailureDetail(message);
      }
    } catch (_) {}
  }

  final messageField = RegExp(r'"message"\s*:\s*("(?:\\.|[^"\\])*")');
  for (final line in lines.reversed) {
    final encoded = messageField.firstMatch(line)?.group(1);
    if (encoded == null) {
      continue;
    }
    try {
      final message = jsonDecode(encoded);
      if (message is String && message.trim().isNotEmpty) {
        return _capFailureDetail(message);
      }
    } catch (_) {}
  }

  final detail = lines.reversed.firstWhere(
    (line) => !_isJsonStructureLine(line),
    orElse: () => combined,
  );
  return _capFailureDetail(detail);
}

String? _messageFromJson(Object? value) {
  if (value is Map) {
    final nestedError = _messageFromJson(value['error']);
    if (nestedError != null) {
      return nestedError;
    }
    final message = value['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    for (final nested in value.values) {
      final nestedMessage = _messageFromJson(nested);
      if (nestedMessage != null) {
        return nestedMessage;
      }
    }
  } else if (value is List) {
    for (final nested in value) {
      final nestedMessage = _messageFromJson(nested);
      if (nestedMessage != null) {
        return nestedMessage;
      }
    }
  } else if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

bool _isJsonStructureLine(String line) {
  return const <String>{'{', '}', '[', ']', '},', '],', ','}.contains(line);
}

String _capFailureDetail(String detail) {
  final trimmed = detail.trim();
  return trimmed.length > _maxAiTextFailureDetailLength
      ? '${trimmed.substring(0, _maxAiTextFailureDetailLength).trimRight()}...'
      : trimmed;
}
