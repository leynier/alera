import 'dart:convert';

const int _maxAiTextFailureDetailLength = 1000;

String? aiTextProcessFailureDetail(String stdout, String stderr) {
  for (final output in <String>[stderr, stdout]) {
    final lines = _failureLines(output);
    if (lines.isEmpty) {
      continue;
    }
    final structured = _structuredFailureMessage(lines);
    if (structured != null) {
      return _capFailureDetail(structured);
    }
    for (final line in lines.reversed) {
      if (_isPlainFailureLine(line)) {
        return _capFailureDetail(line);
      }
    }
  }
  return null;
}

String? _messageFromJson(Object? value) {
  if (value is Map) {
    for (final key in const <String>[
      'error',
      'errors',
      'message',
      'detail',
      'reason',
      'failure',
    ]) {
      final nestedMessage = _messageFromJson(value[key]);
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

List<String> _failureLines(String output) {
  return output
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

String? _structuredFailureMessage(List<String> lines) {
  for (final line in lines.reversed) {
    try {
      final message = _messageFromJson(jsonDecode(line));
      if (message != null) {
        return message;
      }
    } catch (_) {}
  }
  final errorField = RegExp(
    r'"(?:error|message|detail|reason|failure)"\s*:\s*("(?:\\.|[^"\\])*")',
  );
  for (final line in lines.reversed) {
    final encoded = errorField.firstMatch(line)?.group(1);
    if (encoded == null) {
      continue;
    }
    try {
      final message = jsonDecode(encoded);
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    } catch (_) {}
  }
  return null;
}

bool _isPlainFailureLine(String line) {
  if (_isJsonStructureLine(line) || RegExp(r'^"[^"\\]+"\s*:').hasMatch(line)) {
    return false;
  }
  try {
    jsonDecode(line);
    return false;
  } catch (_) {
    return true;
  }
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
