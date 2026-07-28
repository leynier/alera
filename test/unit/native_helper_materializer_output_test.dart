import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/native_helpers/native_helper_manifest.dart';
import '../../tool/native_helpers/native_helper_materializer.dart';

void main() {
  test('replaces precreated nested empty output directories', () async {
    final fixture = await _MaterializerFixture.create();
    addTearDown(fixture.dispose);
    Directory(
      p.join(fixture.output.path, 'android', 'scrcpy', '4.0'),
    ).createSync(recursive: true);

    await fixture.prepare();

    await verifyNativeHelperBundle(
      platform: 'linux',
      emulatorRoot: fixture.output,
      expected: fixture.manifest,
    );
  });

  test('rejects a recursively nested unmanaged file', () async {
    final fixture = await _MaterializerFixture.create();
    addTearDown(fixture.dispose);
    final nested = Directory(p.join(fixture.output.path, 'precreated'))
      ..createSync(recursive: true);
    File(p.join(nested.path, 'unmanaged.txt')).writeAsStringSync('user data');

    await expectLater(
      fixture.prepare(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Refusing to replace unmanaged native helper output'),
        ),
      ),
    );
  });

  test(
    'rejects a recursively nested unmanaged link',
    () async {
      final fixture = await _MaterializerFixture.create();
      addTearDown(fixture.dispose);
      final nested = Directory(p.join(fixture.output.path, 'precreated'))
        ..createSync(recursive: true);
      final target = File(p.join(fixture.root.path, 'link-target'))
        ..writeAsStringSync('user data');
      Link(p.join(nested.path, 'unmanaged-link')).createSync(target.path);

      await expectLater(
        fixture.prepare(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Refusing to replace unmanaged native helper output'),
          ),
        ),
      );
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links requires extra privileges on Windows.'
        : false,
  );
}

final class _MaterializerFixture {
  _MaterializerFixture({
    required this.root,
    required this.manifest,
    required this.materializer,
    required this.output,
    required this.cache,
  });

  static Future<_MaterializerFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'alera-native-helper-output-',
    );
    final repository = Directory(p.join(root.path, 'repository'))
      ..createSync(recursive: true);
    final notices = Directory(p.join(repository.path, 'notices', 'licenses'))
      ..createSync(recursive: true);
    File(
      p.join(repository.path, 'notices', 'NOTICE.md'),
    ).writeAsStringSync('Test notices.\n');
    File(
      p.join(notices.path, 'Apache-2.0.txt'),
    ).writeAsStringSync('Test license.\n');
    final payload = utf8.encode('scrcpy payload');
    final digest = sha256.convert(payload).toString();
    final manifest = NativeHelperManifest.read(
      File(p.join(repository.path, 'manifest.json'))..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'noticeDirectory': 'notices',
          'assets': <Object?>[
            <String, Object?>{
              'id': 'scrcpy-server',
              'version': '4.0',
              'platforms': <String>['linux'],
              'sourceUrl': 'https://example.invalid/scrcpy-server',
              'sourceSha256': digest,
              'sourceCommit': '0123456789abcdef0123456789abcdef01234567',
              'payloadSha256': digest,
              'relativePath': 'android/scrcpy/4.0/scrcpy-server',
              'archiveMember': null,
              'executable': false,
              'license': 'Apache-2.0',
              'licensePath': 'licenses/Apache-2.0.txt',
            },
          ],
        }),
      ),
    );
    return _MaterializerFixture(
      root: root,
      manifest: manifest,
      materializer: NativeHelperMaterializer(
        repositoryRoot: repository,
        manifest: manifest,
        downloader: (_, output) => output.writeAsBytes(payload, flush: true),
      ),
      output: Directory(p.join(root.path, 'prepared')),
      cache: Directory(p.join(root.path, 'cache')),
    );
  }

  final Directory root;
  final NativeHelperManifest manifest;
  final NativeHelperMaterializer materializer;
  final Directory output;
  final Directory cache;

  Future<void> prepare() {
    return materializer.prepare(
      platform: 'linux',
      output: output,
      cache: cache,
    );
  }

  Future<void> dispose() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }
}
