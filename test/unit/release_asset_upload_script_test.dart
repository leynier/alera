import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('tool/release/upload_release_assets.sh');

  test('routes desktop and mobile uploads through the resilient script', () {
    final workflow = File('.github/workflows/release-cut.yml')
        .readAsStringSync();

    expect(
      'bash tool/release/upload_release_assets.sh'.allMatches(workflow).length,
      2,
    );
    expect(workflow, isNot(contains('run: gh release upload')));
    expect(workflow, contains('delete_unpublished_release()'));
  });

  test('uploads assets sequentially and retries a failed asset', () {
    if (Platform.isWindows) {
      return;
    }
    final temp = Directory.systemTemp.createTempSync(
      'alera-release-asset-upload-',
    );
    try {
      final bin = Directory('${temp.path}/bin')..createSync();
      final log = File('${temp.path}/gh.log');
      final state = File('${temp.path}/failed-once');
      final first = File('${temp.path}/first.bin')..writeAsStringSync('first');
      final second = File('${temp.path}/second.bin')
        ..writeAsStringSync('second');
      final fakeGh = File('${bin.path}/gh')
        ..writeAsStringSync('''#!/usr/bin/env bash
set -euo pipefail
asset="\${4:?missing asset}"
name="\${asset##*/}"
echo "\$name" >>"\$FAKE_GH_LOG"
if [[ "\$name" == "first.bin" && ! -e "\$FAKE_GH_STATE" ]]; then
  touch "\$FAKE_GH_STATE"
  exit 1
fi
''');
      final fakeSleep = File('${bin.path}/sleep')
        ..writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
      final chmod = Process.runSync('chmod', <String>[
        '+x',
        fakeGh.path,
        fakeSleep.path,
      ]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());

      final environment = Map<String, String>.from(Platform.environment)
        ..['PATH'] = '${bin.path}:${Platform.environment['PATH'] ?? ''}'
        ..['FAKE_GH_LOG'] = log.path
        ..['FAKE_GH_STATE'] = state.path;
      final result = Process.runSync('bash', <String>[
        script.path,
        'v1.2.3',
        'owner/repository',
        first.path,
        second.path,
      ], environment: environment);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(log.readAsLinesSync(), <String>[
        'first.bin',
        'first.bin',
        'second.bin',
      ]);
      expect(result.stdout, contains('retrying'));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('rejects duplicate release asset names before uploading', () {
    if (Platform.isWindows) {
      return;
    }
    final temp = Directory.systemTemp.createTempSync(
      'alera-release-asset-duplicates-',
    );
    try {
      final firstDirectory = Directory('${temp.path}/first')..createSync();
      final secondDirectory = Directory('${temp.path}/second')..createSync();
      final first = File('${firstDirectory.path}/asset.bin')
        ..writeAsStringSync('first');
      final second = File('${secondDirectory.path}/asset.bin')
        ..writeAsStringSync('second');

      final result = Process.runSync('bash', <String>[
        script.path,
        'v1.2.3',
        'owner/repository',
        first.path,
        second.path,
      ]);

      expect(result.exitCode, 64);
      expect(
        result.stderr,
        contains('Duplicate release asset name: asset.bin'),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
