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
abstract final class AppLogger._() {
  static bool _configured = false;
  static RotatingLogSink? _sink;
  static io.Directory? _directory;
  static void Function(String) _consoleWriter = _writeToStdout;
  static bool _consoleAvailable = true;
  static int _consoleGeneration = 0;

  static RotatingLogSink? get sink => _sink;
  static io.Directory? get logDirectory => _directory;

  static Future<io.Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return io.Directory(p.join(support.path, kAppLogDirectoryName));
  }

  static Future<void> configure({
    Level level = Level.INFO,
    io.Directory? directory,
    void Function(String)? consoleWriter,
    Future<void>? consoleDone,
  }) async {
    if (_configured) {
      return;
    }
    _configured = true;
    Logger.root.level = level;
    _consoleWriter = consoleWriter ?? _writeToStdout;
    _consoleAvailable = true;
    final consoleGeneration = ++_consoleGeneration;
    final consoleCompletion =
        consoleDone ?? (consoleWriter == null ? io.stdout.done : null);
    if (consoleCompletion != null) {
      unawaited(
        consoleCompletion.then<void>(
          (_) => _disableConsole(consoleGeneration),
          onError: (Object _, StackTrace _) {
            _disableConsole(consoleGeneration);
          },
        ),
      );
    }

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
    _writeConsoleRecord(record);
    _writeFileRecord(record);
  }

  static void _writeConsoleRecord(LogRecord record) {
    if (!_consoleAvailable) {
      return;
    }
    try {
      // Plain text so a foreground `flutter run` stays readable, but redacted
      // like the file: console output gets pasted into bug reports too.
      _consoleWriter(
        '[${record.level.name}] ${record.loggerName}: '
        '${redactLogText(record.message)}',
      );
    } on Object {
      // A GUI process may have no valid stdout handle. Do not report this
      // through Logger because that would re-enter this listener recursively.
      _consoleAvailable = false;
    }
  }

  static void _writeFileRecord(LogRecord record) {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    try {
      unawaited(
        sink.writeLine(
          formatLogRecordLine(
            timestamp: record.time,
            level: record.level.name,
            source: 'app',
            logger: record.loggerName,
            message: record.message,
            error: record.error,
            stackTrace: record.stackTrace,
          ),
        ),
      );
    } on Object {
      // Formatting is part of the sink boundary and must not recurse through
      // the global error handlers. Asynchronous file errors are caught by the
      // sink's serialized write queue.
    }
  }

  static void _writeToStdout(String line) => io.stdout.writeln(line);

  static void _disableConsole(int generation) {
    if (_consoleGeneration == generation) {
      _consoleAvailable = false;
    }
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
    _consoleWriter = _writeToStdout;
    _consoleAvailable = true;
    _consoleGeneration++;
    _configured = false;
    Logger.root.clearListeners();
  }
}
