import 'dart:async';
import 'dart:io' as io;

import 'package:alera/src/shared/infra/logging/log_record_formatter.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:alera/src/shared/infra/logging/rotating_log_sink.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Name of the directory holding app logs, under the application support dir.
const String kAppLogDirectoryName = 'logs';
const String kAppLogBaseName = 'alera';

/// Configures application logging.
///
/// Logs go to a rotated file as well as stdout: a packaged desktop build has no
/// console attached, so stdout alone means an error that happens on a user's
/// machine leaves nothing behind to review.
abstract final class AppLogger {
  AppLogger._();

  static bool _configured = false;
  static RotatingLogSink? _sink;
  static io.Directory? _directory;

  static RotatingLogSink? get sink => _sink;
  static io.Directory? get logDirectory => _directory;

  static Future<io.Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return io.Directory(p.join(support.path, kAppLogDirectoryName));
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
        baseName: kAppLogBaseName,
      );
    } on Object {
      // Losing the file sink must not take the app down; stdout still works.
      _sink = null;
    }

    Logger.root.onRecord.listen(_handleRecord);
  }

  static void _handleRecord(LogRecord record) {
    // Plain text so a foreground `flutter run` stays readable, but redacted
    // like the file: console output gets pasted into bug reports too.
    io.stdout.writeln(
      '[${record.level.name}] ${record.loggerName}: '
      '${redactLogText(record.message)}',
    );
    unawaited(
      _sink?.writeLine(
            formatLogRecordLine(
              timestamp: record.time,
              level: record.level.name,
              source: 'app',
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

  /// Test seam: lets a test reconfigure logging with its own directory.
  static Future<void> resetForTesting() async {
    await _sink?.close();
    _sink = null;
    _directory = null;
    _configured = false;
    Logger.root.clearListeners();
  }
}
