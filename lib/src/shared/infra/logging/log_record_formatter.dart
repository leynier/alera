import 'dart:convert';

import 'package:alera/src/shared/infra/logging/log_redaction.dart';

/// Serializes a log record as one JSON object per line.
///
/// JSON Lines rather than free-form text because the diagnostics bundle merges
/// app and runtime logs into a single timeline, which means both sides have to
/// agree on a machine-readable shape.
String formatLogRecordLine({
  required DateTime timestamp,
  required String level,
  required String source,
  required String logger,
  required String message,
  Object? error,
  StackTrace? stackTrace,
}) {
  final record = <String, Object?>{
    'ts': timestamp.toUtc().toIso8601String(),
    'level': redactLogText(level),
    'source': redactLogText(source),
    // Logger names are the context supplied by global error handlers. Apply
    // the same bound as messages so context cannot defeat the record budget.
    'logger': redactLogText(logger),
    'msg': redactLogText(message),
    // The previous logger dropped these even though call sites passed them,
    // which left every warning without the detail that made it actionable.
    // Error and StackTrace expose only toString, so that conversion can be
    // arbitrary for a custom object. Once a string exists, redactLogText
    // bounds it before regex work and JSON serialization.
    if (error != null) 'error': redactLogText(error.toString()),
    if (stackTrace != null) 'stack': redactLogText(stackTrace.toString()),
  };
  return jsonEncode(record);
}
