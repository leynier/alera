import 'dart:convert';
import 'dart:io';

import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:alera/src/shared/infra/logging/log_record_formatter.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('alera-app-logger');
    await AppLogger.resetForTesting();
    resetRegisteredLogSecrets();
  });

  tearDown(() async {
    await AppLogger.resetForTesting();
    resetRegisteredLogSecrets();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  Future<List<Map<String, Object?>>> readRecords() async {
    await AppLogger.flush();
    final file = AppLogger.sink!.fileFor(0);
    return file
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();
  }

  group('formatLogRecordLine', () {
    test('emits the agreed schema', () {
      final line = formatLogRecordLine(
        timestamp: DateTime.utc(2026, 7, 28, 10, 30),
        level: 'WARNING',
        source: 'app',
        logger: 'AppWindowBootstrap',
        message: 'database unavailable',
      );

      final record = jsonDecode(line) as Map<String, Object?>;
      expect(record['ts'], '2026-07-28T10:30:00.000Z');
      expect(record['level'], 'WARNING');
      expect(record['source'], 'app');
      expect(record['logger'], 'AppWindowBootstrap');
      expect(record['msg'], 'database unavailable');
      expect(record.containsKey('error'), isFalse);
      expect(record.containsKey('stack'), isFalse);
    });

    test('redacts the message, the error and the stack', () {
      registerLogSecret('formatter-secret-token');
      final line = formatLogRecordLine(
        timestamp: DateTime.utc(2026, 7, 28),
        level: 'SEVERE',
        source: 'app',
        logger: 'Test',
        message: 'attach failed for formatter-secret-token',
        error: 'token=formatter-secret-token',
        stackTrace: StackTrace.fromString('at formatter-secret-token'),
      );

      expect(line, isNot(contains('formatter-secret-token')));
      final record = jsonDecode(line) as Map<String, Object?>;
      expect(record['error'], contains(kRedactedPlaceholder));
      expect(record['stack'], contains(kRedactedPlaceholder));
    });
  });

  group('AppLogger', () {
    test('writes log records to the rotated file', () async {
      await AppLogger.configure(directory: root);

      Logger('Workbench').info('workspace opened');

      final records = await readRecords();
      expect(records, hasLength(1));
      expect(records.single['msg'], 'workspace opened');
      expect(records.single['logger'], 'Workbench');
      expect(records.single['source'], 'app');
    });

    test('keeps the error and stack trace call sites already pass', () async {
      await AppLogger.configure(directory: root);

      Logger('AgentAwakeService').warning(
        'assertion failed',
        StateError('no session'),
        StackTrace.fromString('#0 fakeFrame'),
      );

      final records = await readRecords();
      expect(records.single['error'], contains('no session'));
      expect(records.single['stack'], contains('fakeFrame'));
    });

    test('records an error that reached a global handler', () async {
      await AppLogger.configure(directory: root);

      AppLogger.recordError(
        StateError('boom'),
        StackTrace.fromString('#0 zoneFrame'),
        context: 'Zone',
      );

      final records = await readRecords();
      expect(records.single['level'], 'SEVERE');
      expect(records.single['logger'], 'Zone');
      expect(records.single['error'], contains('boom'));
    });

    test('honors the configured level', () async {
      await AppLogger.configure(level: Level.SEVERE, directory: root);

      Logger('Quiet').info('should be dropped');
      Logger('Loud').severe('should be kept');

      final records = await readRecords();
      expect(records, hasLength(1));
      expect(records.single['msg'], 'should be kept');
    });

    test('configure is idempotent so records are not written twice', () async {
      await AppLogger.configure(directory: root);
      await AppLogger.configure(directory: root);

      Logger('Workbench').info('once');

      expect(await readRecords(), hasLength(1));
    });

    test('a secret registered at runtime never reaches the file', () async {
      await AppLogger.configure(directory: root);
      registerLogSecret('runtime-host-token-abc123');

      Logger(
        'TerminalHost',
      ).info('launching host with runtime-host-token-abc123');

      await AppLogger.flush();
      final contents = AppLogger.sink!.fileFor(0).readAsStringSync();
      expect(contents, isNot(contains('runtime-host-token-abc123')));
      expect(contents, contains(kRedactedPlaceholder));
    });
  });
}
