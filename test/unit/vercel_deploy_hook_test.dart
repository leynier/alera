import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/release/trigger_vercel_deploy_hook.sh');

  test('skips non-stable channels without requiring the production secret', () {
    if (Platform.isWindows) {
      return;
    }
    final temp = Directory.systemTemp.createTempSync('alera-vercel-hook-rc-');
    try {
      final fakeBin = Directory('${temp.path}/bin')..createSync();
      final curlLog = File('${temp.path}/curl.log');
      _writeExecutable(File('${fakeBin.path}/curl'), '''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' called >>"\$ALERA_CURL_LOG"
exit 99
''');

      final result = _run(
        script,
        <String>['rc'],
        temp: temp,
        fakeBin: fakeBin,
        extraEnvironment: <String, String>{'ALERA_CURL_LOG': curlLog.path},
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Skipping the production landing'));
      expect(curlLog.existsSync(), isFalse);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('requires the production hook secret for stable publication', () {
    if (Platform.isWindows) {
      return;
    }
    final temp = Directory.systemTemp.createTempSync(
      'alera-vercel-hook-missing-',
    );
    try {
      final result = _run(script, <String>['stable'], temp: temp);

      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('VERCEL_PRODUCTION_DEPLOY_HOOK is required'),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('accepts a successful hook response without printing the secret', () {
    if (Platform.isWindows) {
      return;
    }
    final temp = Directory.systemTemp.createTempSync('alera-vercel-hook-ok-');
    try {
      final fakeBin = Directory('${temp.path}/bin')..createSync();
      final curlLog = File('${temp.path}/curl.log');
      _writeExecutable(File('${fakeBin.path}/curl'), '''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$*" >"\$ALERA_CURL_LOG"
config=''
previous=''
for argument do
  if [[ "\$previous" == '--config' ]]; then
    config="\$argument"
  fi
  previous="\$argument"
done
grep -Fq 'secret-value' "\$config"
output=''
previous=''
for argument do
  if [[ "\$previous" == '--output' ]]; then
    output="\$argument"
  fi
  previous="\$argument"
done
printf 'accepted' >"\$output"
printf '201'
''');
      const secret = 'https://api.vercel.invalid/hook/secret-value';

      final result = _run(
        script,
        <String>['stable'],
        temp: temp,
        fakeBin: fakeBin,
        extraEnvironment: <String, String>{
          'ALERA_CURL_LOG': curlLog.path,
          'VERCEL_PRODUCTION_DEPLOY_HOOK': secret,
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Vercel accepted'));
      expect(result.stdout, isNot(contains(secret)));
      expect(result.stderr, isNot(contains(secret)));
      expect(curlLog.readAsStringSync(), contains('--config'));
      expect(curlLog.readAsStringSync(), isNot(contains(secret)));
      expect(
        File('${temp.path}/alera-vercel-deploy-hook-config').existsSync(),
        isFalse,
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('reports a non-success hook response without exposing the secret', () {
    if (Platform.isWindows) {
      return;
    }
    final temp = Directory.systemTemp.createTempSync('alera-vercel-hook-fail-');
    try {
      final fakeBin = Directory('${temp.path}/bin')..createSync();
      final curlLog = File('${temp.path}/curl.log');
      _writeExecutable(File('${fakeBin.path}/curl'), '''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$*" >"\$ALERA_CURL_LOG"
config=''
previous=''
for argument do
  if [[ "\$previous" == '--config' ]]; then
    config="\$argument"
  fi
  previous="\$argument"
done
grep -Fq 'failure-secret' "\$config"
printf '500'
''');
      const secret = 'https://api.vercel.invalid/hook/failure-secret';

      final result = _run(
        script,
        <String>['stable'],
        temp: temp,
        fakeBin: fakeBin,
        extraEnvironment: <String, String>{
          'ALERA_CURL_LOG': curlLog.path,
          'VERCEL_PRODUCTION_DEPLOY_HOOK': secret,
        },
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('returned HTTP 500'));
      expect(result.stdout, isNot(contains(secret)));
      expect(result.stderr, isNot(contains(secret)));
      expect(curlLog.readAsStringSync(), isNot(contains(secret)));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}

ProcessResult _run(
  File script,
  List<String> arguments, {
  required Directory temp,
  Directory? fakeBin,
  Map<String, String> extraEnvironment = const <String, String>{},
}) {
  final environment = Map<String, String>.from(Platform.environment)
    ..['RUNNER_TEMP'] = temp.path
    ..addAll(extraEnvironment);
  if (fakeBin != null) {
    environment['PATH'] =
        '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}';
  }
  return Process.runSync('bash', <String>[
    script.path,
    ...arguments,
  ], environment: environment);
}

void _writeExecutable(File file, String contents) {
  file.writeAsStringSync(contents);
  final chmod = Process.runSync('chmod', <String>['+x', file.path]);
  if (chmod.exitCode != 0) {
    throw StateError('Could not mark ${file.path} executable: ${chmod.stderr}');
  }
}
