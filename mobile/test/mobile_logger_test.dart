import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/core/logging/log_redaction.dart';
import 'package:alera_mobile/src/core/logging/mobile_logger.dart';
import 'package:alera_mobile/src/core/logging/rotating_log_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('alera-mobile-logger');
    await MobileLogger.resetForTesting();
    resetRegisteredLogSecrets();
  });

  tearDown(() async {
    await MobileLogger.resetForTesting();
    resetRegisteredLogSecrets();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  Future<List<Map<String, Object?>>> readRecords() async {
    await MobileLogger.flush();
    return MobileLogger.sink!
        .fileFor(0)
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();
  }

  group('MobileLogger', () {
    test('writes records tagged as coming from mobile', () async {
      await MobileLogger.configure(directory: root);

      Logger('HostList').info('loaded paired hosts');

      final records = await readRecords();
      expect(records.single['source'], 'mobile');
      expect(records.single['msg'], 'loaded paired hosts');
      expect(records.single['logger'], 'HostList');
    });

    test('keeps the error and stack trace', () async {
      await MobileLogger.configure(directory: root);

      Logger('MobileRuntimeClient').warning(
        'runtime connection failed',
        StateError('socket closed'),
        .fromString('#0 fakeFrame'),
      );

      final records = await readRecords();
      expect(records.single['error'], contains('socket closed'));
      expect(records.single['stack'], contains('fakeFrame'));
    });

    test('never writes a registered device token', () async {
      await MobileLogger.configure(directory: root);
      registerLogSecret('device-token-abcdef123456');

      Logger('MobileRuntimeClient')
          .info('authenticated with device-token-abcdef123456');

      await MobileLogger.flush();
      final contents = MobileLogger.sink!.fileFor(0).readAsStringSync();
      expect(contents, isNot(contains('device-token-abcdef123456')));
      expect(contents, contains(kRedactedPlaceholder));
    });

    test('records an error that reached a global handler', () async {
      await MobileLogger.configure(directory: root);

      MobileLogger.recordError(
        StateError('boom'),
        .fromString('#0 zoneFrame'),
        context: 'Zone',
      );

      final records = await readRecords();
      expect(records.single['level'], 'SEVERE');
      expect(records.single['logger'], 'Zone');
    });

    test('logFiles lists what an export would attach', () async {
      await MobileLogger.configure(directory: root);

      Logger('HostList').info('one');
      await MobileLogger.flush();

      expect(MobileLogger.logFiles(), hasLength(1));
    });
  });

  group('mobile rotation defaults', () {
    test('are smaller than the desktop caps', () {
      expect(kDefaultLogMaxBytes, 2 * 1024 * 1024);
      expect(kDefaultLogMaxFiles, 3);
    });

    test('rotate and drop the oldest file', () async {
      final sink = RotatingLogSink(
        directory: root,
        baseName: 'alera-mobile',
        maxBytes: 100,
        maxFiles: 3,
      );

      for (var index = 0; index < 6; index++) {
        await sink.writeLine('x' * 79);
      }
      await sink.close();

      expect(sink.fileFor(2).existsSync(), isTrue);
      expect(sink.fileFor(3).existsSync(), isFalse);
    });
  });

  group('redaction', () {
    test('masks keyed secrets and bearer headers', () {
      final redacted = redactLogText(
        'deviceToken=abc123def456 and Bearer eyJhbGciOi.payload',
      );

      expect(redacted, isNot(contains('abc123def456')));
      expect(redacted, isNot(contains('eyJhbGciOi.payload')));
    });
  });
}
