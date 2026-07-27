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
