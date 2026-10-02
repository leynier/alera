import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/rust/frb_generated.dart';
import 'package:alera/src/shared/infra/process/rust_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Exercises the native runner end to end. It cannot live under `test/` because
/// the bridge needs the compiled Rust library, and it is the only coverage the
/// streaming path has: `process_start` is reachable only through a real
/// `StreamSink`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const runner = RustProcessRunner();

  setUpAll(() async {
    await RustLib.init();
  });

  test('run captures stdout and the exit code', () async {
    final result = await runner.run('git', const <String>['--version']);

    expect(result.exitCode, 0);
    expect(result.stdout, startsWith('git version'));
  });

  test('run reports a failing command through stderr', () async {
    final directory = await Directory.systemTemp.createTemp('alera-process-');
    addTearDown(() => directory.delete(recursive: true));

    final result = await runner.run('git', const <String>[
      'rev-parse',
      '--verify',
      'refs/heads/missing',
    ], workingDirectory: directory.path);

    expect(result.exitCode, isNot(0));
    expect(result.stderr.toLowerCase(), contains('fatal'));
  });

  test(
    'runWithOutputBudget captures both streams under one native budget',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final result = await runner.runWithOutputBudget('sh', const <String>[
        '-c',
        'head -c 30000 /dev/zero; head -c 30000 /dev/zero >&2',
      ], maxOutputBytes: 65536);

      expect(result.exitCode, 0);
      expect(result.stdout, hasLength(30000));
      expect(result.stderr, hasLength(30000));
    },
  );

  test('runWithOutputBudget rejects an overflowing native capture', () async {
    if (Platform.isWindows) {
      return;
    }
    await expectLater(
      runner.runWithOutputBudget('sh', const <String>[
        '-c',
        'yes x',
      ], maxOutputBytes: 4096),
      throwsA(
        isA<ProcessException>().having(
          (error) => error.message,
          'message',
          contains('combined process output limit'),
        ),
      ),
    );
  });

  test(
    'runWithOutputBudget preserves lossy UTF8 decoding and exit status',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final result = await runner.runWithOutputBudget('sh', const <String>[
        '-c',
        r"printf '\377\376ok'; printf 'bad' >&2; exit 3",
      ], maxOutputBytes: 1024);

      expect(result.exitCode, 3);
      expect(result.stdout, '��ok');
      expect(result.stderr, 'bad');
    },
  );

  test(
    'runWithOutputBudget times out and cleans up a waiting child tree',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final stopwatch = Stopwatch()..start();
      await expectLater(
        runner.runWithOutputBudget(
          'sh',
          const <String>['-c', 'sleep 10 & wait'],
          maxOutputBytes: 1024,
          timeout: const Duration(milliseconds: 25),
        ),
        throwsA(
          isA<ProcessException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test('runWithOutputBudget allows a documented larger response', () async {
    if (Platform.isWindows) {
      return;
    }
    final result = await runner.runWithOutputBudget('sh', const <String>[
      '-c',
      'head -c 65536 /dev/zero',
    ], maxOutputBytes: 65537);

    expect(result.exitCode, 0);
    expect(result.stdout, hasLength(65536));
  });

  test('start streams stdout and completes with the exit code', () async {
    final process = await runner.start('git', const <String>['--version']);

    final stdout = await process.stdout.transform(utf8.decoder).join();
    expect(await process.exitCode, 0);
    expect(stdout, startsWith('git version'));
  });

  test('start writes to stdin and sees it echoed back', () async {
    final process = await runner.start('git', const <String>[
      'hash-object',
      '--stdin',
    ]);
    process.stdinWrite(utf8.encode('alera'));
    process.stdinClose();

    final stdout = await process.stdout.transform(utf8.decoder).join();
    expect(await process.exitCode, 0);
    // `git hash-object` only answers once stdin reaches EOF.
    expect(stdout.trim(), hasLength(40));
  });

  test('start chunks oversized stdin and retries a saturated writer', () async {
    if (Platform.isWindows) {
      return;
    }
    final process = await runner.start('sh', const <String>[
      '-c',
      'sleep 0.2; wc -c',
    ]);
    final payload = List<int>.filled(5 * 1024 * 1024, 65);
    process.stdinWrite(payload);
    process.stdinClose();

    final stdout = await process.stdout.transform(utf8.decoder).join();
    expect(await process.exitCode, 0);
    expect(int.parse(stdout.trim()), payload.length);
  });

  test(
    'start stops pending stdin retries when the process is killed',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final process = await runner.start('sh', const <String>['-c', 'sleep 5']);
      process.stdinWrite(List<int>.filled(5 * 1024 * 1024, 65));
      expect(process.kill(), isTrue);
      expect(
        await process.exitCode.timeout(const Duration(seconds: 2)),
        isNot(0),
      );
    },
  );

  test('start reports Dart stdin queue overflow through exitCode', () async {
    if (Platform.isWindows) {
      return;
    }
    final process = await runner.start('sh', const <String>['-c', 'sleep 5']);
    process.stdinWrite(List<int>.filled(8 * 1024 * 1024, 65));
    process.stdinWrite(const <int>[65]);

    await expectLater(process.exitCode, throwsA(isA<ProcessException>()));
  });

  test('stdin overflow ignores late native output events', () async {
    if (Platform.isWindows) {
      return;
    }
    final process = await runner.start('sh', const <String>[
      '-c',
      'printf first; dd if=/dev/zero bs=65536 count=64 2>/dev/null; sleep 5',
    ]);
    final firstOutput = Completer<void>();
    var capturedBytes = 0;
    final stdoutSubscription = process.stdout.listen((chunk) {
      capturedBytes += chunk.length;
      if (chunk.isNotEmpty && !firstOutput.isCompleted) {
        firstOutput.complete();
      }
    });
    final stderrDone = process.stderr.drain<void>();

    await firstOutput.future.timeout(const Duration(seconds: 2));
    process.stdinWrite(List<int>.filled(8 * 1024 * 1024, 65));
    process.stdinWrite(const <int>[65]);

    await expectLater(
      process.exitCode.timeout(const Duration(seconds: 2)),
      throwsA(isA<ProcessException>()),
    );
    await stdoutSubscription.asFuture<void>().timeout(
      const Duration(seconds: 2),
    );
    await stderrDone.timeout(const Duration(seconds: 2));
    expect(capturedBytes, greaterThan(0));
  });

  test('start reports a write after stdin close through exitCode', () async {
    if (Platform.isWindows) {
      return;
    }
    final process = await runner.start('sh', const <String>['-c', 'sleep 5']);
    process.stdinClose();
    process.stdinWrite(const <int>[65]);

    await expectLater(process.exitCode, throwsA(isA<ProcessException>()));
  });

  test('kill ends a process that would otherwise keep running', () async {
    final process = await runner.start('git', const <String>[
      'hash-object',
      '--stdin',
    ]);

    expect(process.kill(), isTrue);
    expect(await process.exitCode, isNot(0));
  });

  test(
    'a missing executable fails through the shell, as it did before',
    () async {
      // Parity with `runInShell: true`: the shell starts, cannot find the
      // command, and reports it on stderr instead of failing the spawn.
      final result = await runner.run('alera-does-not-exist', const <String>[]);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, isNotEmpty);
    },
  );
}
