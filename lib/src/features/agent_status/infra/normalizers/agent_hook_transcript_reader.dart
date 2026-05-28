part of '../agent_hook_event_normalizer.dart';

String? _readLastAssistantFromTranscript(Object? transcriptPath) {
  return _readLastTextFromTranscript(transcriptPath, _assistantTextFromLine);
}

String? _readLastUserPromptFromTranscript(Object? transcriptPath) {
  return _readLastTextFromTranscript(transcriptPath, _userPromptTextFromLine);
}

String? _readLastTextFromTranscript(
  Object? transcriptPath,
  String? Function(String line) extract,
) {
  if (transcriptPath is! String || transcriptPath.trim().isEmpty) {
    return null;
  }
  try {
    final file = File(transcriptPath);
    final length = file.lengthSync();
    if (length <= 0) {
      return null;
    }
    final start = length > _transcriptMaxScanBytes
        ? length - _transcriptMaxScanBytes
        : 0;
    final bytes = file.openSync()..setPositionSync(start);
    try {
      final text = utf8.decode(
        bytes.readSync(length - start),
        allowMalformed: true,
      );
      final lines = text.split('\n');
      for (var index = lines.length - 1; index >= 0; index--) {
        final line = lines[index].trim();
        if (line.isEmpty) {
          continue;
        }
        final extracted = extract(line);
        if (extracted != null) {
          return _normalizeMultiline(extracted, 8000);
        }
      }
    } finally {
      bytes.closeSync();
    }
  } catch (_) {}
  return null;
}

String? _assistantTextFromLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      return null;
    }
    final record = Map<String, Object?>.from(decoded);
    if (record['type'] == 'assistant.message' && record['data'] is Map) {
      final data = Map<String, Object?>.from(record['data'] as Map);
      return _assistantContentText(data['content']);
    }
    if (record['source'] == 'MODEL' &&
        record['type'] == 'PLANNER_RESPONSE' &&
        record['content'] is String) {
      return record['content'] as String;
    }
    final message = record['message'] is Map
        ? Map<String, Object?>.from(record['message'] as Map)
        : null;
    final role = record['role'] ?? message?['role'];
    if (role != 'assistant' && record['type'] != 'assistant') {
      return null;
    }
    return _assistantContentText(message?['content'] ?? record['content']);
  } catch (_) {
    return null;
  }
}

String? _assistantContentText(Object? content) {
  if (content is String && content.trim().isNotEmpty) {
    return content;
  }
  if (content is List) {
    for (final part in content) {
      if (part is Map && part['text'] is String) {
        final text = part['text'] as String;
        if (text.trim().isNotEmpty) {
          return text;
        }
      }
    }
  }
  return null;
}

String? _userPromptTextFromLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      return null;
    }
    final record = Map<String, Object?>.from(decoded);
    final source = record['source'];
    final type = record['type'];
    final content = record['content'];
    if ((source == 'USER_EXPLICIT' || source == 'USER') &&
        (type == 'USER_INPUT' || type == 'REQUEST') &&
        content is String) {
      final match = RegExp(
        r'<USER_REQUEST>\s*([\s\S]*?)\s*</USER_REQUEST>',
      ).firstMatch(content);
      final text = (match?.group(1) ?? content).trim();
      return text.isEmpty ? null : text;
    }
  } catch (_) {}
  return null;
}
