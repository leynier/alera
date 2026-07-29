import 'dart:async';
import 'dart:io' as io;

import 'package:alera_mobile/src/core/logging/log_record_formatter.dart';
import 'package:alera_mobile/src/core/logging/log_redaction.dart';
import 'package:alera_mobile/src/core/logging/rotating_log_sink.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String kMobileLogDirectoryName = 'logs';
const String kMobileLogBaseName = 'alera-mobile';

/// Configures logging for the mobile companion.
///
/// The app had no logging at all: every failure was either turned into a
/// SnackBar or dropped, so a problem reported after the fact left nothing to
/// look at. A rotated file on the device is what makes review possible.
abstract final class MobileLogger {
  MobileLogger._();

  static bool _configured = false;
  static RotatingLogSink? _sink;
  static io.Directory? _directory;

  static RotatingLogSink? get sink => _sink;
  static io.Directory? get logDirectory => _directory;

  static Future<io.Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return io.Directory(p.join(support.path, kMobileLogDirectoryName));
  }

  static Future<void> configure({
    Level level = Level.INFO,
    io.Directory? directory,
  }) async {
    if (_configured) {
      return;
    }
    _configured = true;
    Logger.root.level = level;

    try {
      _directory = directory ?? await _defaultDirectory();
      _sink = RotatingLogSink(
        directory: _directory!,
        baseName: kMobileLogBaseName,
      );
    } on Object {
      // A device that refuses the directory must still run the app.
      _sink = null;
    }

    Logger.root.onRecord.listen(_handleRecord);
  }

  static void _handleRecord(LogRecord record) {
    if (kDebugMode) {
      debugPrint(
        '[${record.level.name}] ${record.loggerName}: '
        '${redactLogText(record.message)}',
      );
    }
    unawaited(
      _sink?.writeLine(
            formatLogRecordLine(
              timestamp: record.time,
              level: record.level.name,
              source: 'mobile',
              logger: record.loggerName,
              message: record.message,
              error: record.error,
              stackTrace: record.stackTrace,
            ),
          ) ??
          Future<void>.value(),
    );
  }

  static void setLevel(Level level) => Logger.root.level = level;

  /// Records an error that reached a global handler rather than a logger.
  static void recordError(
    Object error,
    StackTrace? stackTrace, {
    required String context,
  }) {
    Logger(context).severe('unhandled error', error, stackTrace);
  }

  static Future<void> flush() async => _sink?.flush();

  /// Files to attach when the user exports logs, newest first.
  static List<io.File> logFiles() => _sink?.existingFiles() ?? <io.File>[];

  static Future<void> resetForTesting() async {
    await _sink?.close();
    _sink = null;
    _directory = null;
    _configured = false;
    Logger.root.clearListeners();
  }
}
