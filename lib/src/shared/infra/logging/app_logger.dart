import 'package:logging/logging.dart';

class AppLogger {
  AppLogger._();

  static bool _configured = false;

  static void configure({Level level = Level.INFO}) {
    if (_configured) {
      return;
    }
    _configured = true;
    Logger.root.level = level;
    Logger.root.onRecord.listen((record) {
      // Keep log format plain so it is easy to ingest in desktop log files.
      // ignore: avoid_print
      print('[${record.level.name}] ${record.loggerName}: ${record.message}');
    });
  }
}
