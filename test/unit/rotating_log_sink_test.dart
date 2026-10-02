import 'dart:async';
import 'dart:io';

import 'package:alera/src/shared/infra/logging/rotating_log_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('alera-log-sink');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  String lineOf(int bytes) => 'x' * (bytes - 1);

  test('appends to a single file while under the cap', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxBytes: 1024,
      maxFiles: 3,
    );

    await sink.writeLine(lineOf(64));
    await sink.writeLine(lineOf(64));
    await sink.close();

    expect(sink.fileFor(0).lengthSync(), 128);
    expect(sink.fileFor(1).existsSync(), isFalse);
  });

  test('rotates once the cap is exceeded', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxBytes: 100,
      maxFiles: 3,
    );

    await sink.writeLine(lineOf(80));
    await sink.writeLine(lineOf(80));
    await sink.close();

    expect(sink.fileFor(1).existsSync(), isTrue);
    expect(sink.fileFor(0).lengthSync(), 80);
    expect(sink.fileFor(1).lengthSync(), 80);
  });

  test('keeps at most maxFiles and discards the oldest', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxBytes: 100,
      maxFiles: 3,
    );

    for (var index = 0; index < 6; index++) {
      await sink.writeLine(lineOf(80));
    }
    await sink.close();

    expect(sink.fileFor(0).existsSync(), isTrue);
    expect(sink.fileFor(1).existsSync(), isTrue);
    expect(sink.fileFor(2).existsSync(), isTrue);
    expect(sink.fileFor(3).existsSync(), isFalse);
  });

  test('a record larger than the cap is still written', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxBytes: 50,
      maxFiles: 3,
    );

    await sink.writeLine(lineOf(200));
    await sink.close();

    expect(sink.fileFor(0).lengthSync(), 200);
  });

  test('creates the directory on first write', () async {
    final nested = Directory('${root.path}/logs');
    final sink = RotatingLogSink(directory: nested, baseName: 'alera');

    await sink.writeLine('first');
    await sink.close();

    expect(File('${nested.path}/alera.log').existsSync(), isTrue);
  });

  test('preserves write order across a rotation', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxBytes: 40,
      maxFiles: 4,
    );

    // Not awaited individually: this is how the logger actually calls it, so
    // the queue is what has to keep the order.
    final writes = <Future<void>>[
      for (var index = 0; index < 6; index++) sink.writeLine('line-$index'),
    ];
    await Future.wait(writes);
    await sink.close();

    final newest = sink.fileFor(0).readAsStringSync().trim();
    expect(newest, 'line-5');
  });

  test('existingFiles lists only files that are present', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxBytes: 100,
      maxFiles: 3,
    );

    await sink.writeLine(lineOf(80));
    await sink.writeLine(lineOf(80));
    await sink.close();

    expect(sink.existingFiles(), hasLength(2));
  });

  test('writing after close is a no-op rather than an error', () async {
    final sink = RotatingLogSink(directory: root, baseName: 'alera');

    await sink.writeLine('before');
    await sink.close();
    await sink.writeLine('after');

    expect(sink.fileFor(0).readAsStringSync(), 'before\n');
  });

  test('an unwritable log path completes writes without throwing', () async {
    final blocker = File('${root.path}/not-a-directory')
      ..writeAsStringSync('blocker');
    final sink = RotatingLogSink(
      directory: Directory(blocker.path),
      baseName: 'alera',
    );

    await expectLater(sink.writeLine('line'), completes);
    await expectLater(sink.flush(), completes);
    await expectLater(sink.close(), completes);
  });

  test(
    'handles an asynchronous file sink failure without an uncaught error',
    () async {
      if (!Platform.isLinux || !File('/dev/full').existsSync()) {
        return;
      }
      await Link('${root.path}/alera.log').create('/dev/full');
      final sink = RotatingLogSink(
        directory: root,
        baseName: 'alera',
        flushBytes: 1,
      );
      final uncaught = <Object>[];

      await runZonedGuarded(
        () async {
          await sink.writeLine('line');
          await sink.flush();
          await sink.close();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        (error, _) {
          uncaught.add(error);
        },
      );

      expect(uncaught, isEmpty);
    },
  );

  test(
    'pending writes stay bounded when the producer outpaces the sink',
    () async {
      final blocker = File('${root.path}/not-a-directory')
        ..writeAsStringSync('blocker');
      final sink = RotatingLogSink(
        directory: Directory(blocker.path),
        baseName: 'alera',
        maxPendingBytes: 32,
      );

      final writes = <Future<void>>[
        for (var index = 0; index < 1000; index++)
          sink.writeLine('line-$index'),
      ];

      await Future.wait(writes);
      await sink.close();
    },
  );

  test('drops a single record larger than the pending budget', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxPendingBytes: 32,
    );

    await sink.writeLine('x' * 100);
    await sink.close();

    expect(sink.fileFor(0).existsSync(), isFalse);
  });

  test('bounds pending records using their UTF-8 byte length', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxPendingBytes: 5,
    );

    await sink.writeLine('éé');
    await sink.close();

    expect(sink.fileFor(0).readAsBytesSync(), <int>[
      0xc3,
      0xa9,
      0xc3,
      0xa9,
      0x0a,
    ]);
  });

  test('drops an oversized multibyte record before encoding it', () async {
    final sink = RotatingLogSink(
      directory: root,
      baseName: 'alera',
      maxPendingBytes: 4,
    );

    await sink.writeLine('éé');
    await sink.close();

    expect(sink.fileFor(0).existsSync(), isFalse);
  });
}
