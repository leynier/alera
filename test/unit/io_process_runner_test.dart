import 'dart:convert';

import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IoProcessRunner', () {
    const runner = IoProcessRunner();

    test('run captures stdout, stderr, and exit codes', () async {
      final result = await runner.run('sh', <String>[
        '-c',
        "printf 'stdout'; printf 'stderr' >&2; exit 7",
      ]);

      expect(result.exitCode, 7);
      expect(result.stdout, 'stdout');
      expect(result.stderr, 'stderr');
    });

    test('start exposes stdin, stdout, pid, exit code, and default kill', () async {
      final process = await runner.start('sh', <String>['-c', 'cat']);
      process.stdinWrite(utf8.encode('hello from runner\n'));

      final output = await utf8.decoder.bind(process.stdout).first;
      expect(output, contains('hello from runner'));
      expect(process.pid, greaterThan(0));

      expect(process.kill(), isTrue);
      final exitCode = await process.exitCode;
      expect(exitCode, isNot(0));
    });
  });
}
