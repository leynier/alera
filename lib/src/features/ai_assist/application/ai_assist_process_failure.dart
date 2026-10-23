import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/error_reporting/application/user_facing_error_message.dart';

const int _maxAiAssistFailureDetailLength = 1000;

/// The message for a CLI that could not be spawned: it keeps the install
/// guidance and names the actual cause, such as `Codex could not be started:
/// No such file or directory. Check that codex is installed and on PATH.`
String aiAssistProcessStartFailureMessage({
  required String subject,
  required String binary,
  required Object error,
}) {
  final rawCause = error is ProcessException && error.message.trim().isNotEmpty
      ? stripErrorTypePrefixes(error.message)
      : userFacingErrorMessage(error);
  final cause = RegExp(r'[.!?]$').hasMatch(rawCause) ? rawCause : '$rawCause.';
  return '$subject could not be started: $cause Check that $binary is '
      'installed and on PATH.';
}

String? aiAssistProcessFailureDetail(String stdout, String stderr) {
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
  return trimmed.length > _maxAiAssistFailureDetailLength
      ? '${trimmed.substring(0, _maxAiAssistFailureDetailLength).trimRight()}...'
      : trimmed;
}
