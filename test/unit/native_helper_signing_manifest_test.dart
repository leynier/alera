import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/native_helpers/native_helper_manifest.dart';
import '../../tool/native_helpers/native_helper_materializer.dart';
import '../../tool/native_helpers/refresh_signed_native_helper_bundle.dart';

void main() {
  test(
    'refreshes a source-derived helper digest after macOS code signing',
    () async {
      final fixture = await _SigningFixture.create(
        manifestJson: _derivedManifest(),
        initialPayload: utf8.encode('ad-hoc signed payload'),
      );
      addTearDown(fixture.dispose);
      await Process.run('chmod', <String>['755', fixture.payload.path]);
      final before = await fileSha256(fixture.payload);
      fixture.writeGeneratedManifest(before);

      fixture.payload.writeAsBytesSync(
        utf8.encode('developer id signed payload'),
        flush: true,
      );
      await refreshSignedMacosNativeHelperBundle(
        emulatorRoot: fixture.output,
        expected: fixture.manifest,
      );

      final after = await fileSha256(fixture.payload);
      expect(after, isNot(before));
      expect(fixture.generatedSha256, after);
      await verifyNativeHelperBundle(
        platform: 'macos',
        emulatorRoot: fixture.output,
        expected: fixture.manifest,
      );
    },
    skip: Platform.isWindows
        ? 'The executable fixture requires POSIX file permissions.'
        : false,
  );

  test('rejects changes to a content-pinned helper', () async {
    final original = utf8.encode('pinned helper');
    final digest = sha256.convert(original).toString();
    final fixture = await _SigningFixture.create(
      manifestJson: _pinnedManifest(digest),
      initialPayload: original,
    );
    addTearDown(fixture.dispose);
    fixture.writeGeneratedManifest(digest);
    fixture.payload.writeAsStringSync('changed during signing', flush: true);

    await expectLater(
      refreshSignedMacosNativeHelperBundle(
        emulatorRoot: fixture.output,
        expected: fixture.manifest,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('is pinned and cannot change'),
        ),
      ),
    );
    expect(fixture.generatedSha256, digest);
  });

  test('refreshes helper hashes before sealing and re-verifies the app', () {
    final macosSigning = File('tool/release/sign_macos.sh')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final release = File('.github/workflows/release-cut.yml')
        .readAsStringSync();
    final helperSigning = macosSigning.indexOf(
      'sign_macho_files "\$app_path/Contents/Resources/alera"',
    );
    final manifestRefresh = macosSigning.indexOf(
      'refresh_signed_native_helper_bundle.dart',
    );
    final appSigning = macosSigning.indexOf(
      'codesign --force --options runtime --timestamp \\\n'
      '  --entitlements',
    );

    expect(helperSigning, greaterThanOrEqualTo(0));
    expect(manifestRefresh, greaterThan(helperSigning));
    expect(appSigning, greaterThan(manifestRefresh));
    expect(
      release.lastIndexOf('verify_desktop_runtime_bundle.dart'),
      greaterThan(release.indexOf('sign_macos.sh')),
    );
  });
}

final class _SigningFixture({
  required final Directory root,
  required final Directory output,
  required final NativeHelperManifest manifest,
  required final File payload,
}) {
  static Future<_SigningFixture> create({
    required Map<String, Object?> manifestJson,
    required List<int> initialPayload,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'alera-native-helper-signing-',
    );
    final manifestFile = File(p.join(root.path, 'source-manifest.json'))
      ..writeAsStringSync(jsonEncode(manifestJson));
    final manifest = NativeHelperManifest.read(manifestFile);
    final asset = manifest.assetsFor('macos').single;
    final output = Directory(p.join(root.path, 'emulator'))
      ..createSync(recursive: true);
    final payload = File(p.join(output.path, p.fromUri(asset.relativePath)));
    payload.parent.createSync(recursive: true);
    payload.writeAsBytesSync(initialPayload, flush: true);
    File(p.join(output.path, 'NOTICE.md')).writeAsStringSync('Notices.\n');
    final licenses = Directory(p.join(output.path, 'licenses'))
      ..createSync(recursive: true);
    File(p.join(licenses.path, 'Apache-2.0.txt'))
        .writeAsStringSync('Apache license.\n');
    File(p.join(licenses.path, 'BSD-3-Clause.txt'))
        .writeAsStringSync('BSD license.\n');
    return _SigningFixture(
      root: root,
      output: output,
      manifest: manifest,
      payload: payload,
    );
  }

  String get generatedSha256 {
    final generated = jsonDecode(
      File(p.join(output.path, 'manifest.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    final assets = generated['assets']! as List<Object?>;
    return (assets.single! as Map<String, Object?>)['sha256']! as String;
  }

  void writeGeneratedManifest(String digest) {
    File(p.join(output.path, 'manifest.json')).writeAsStringSync(
      jsonEncode(
        manifest.bundleJson(
          'macos',
          payloadSha256ById: <String, String>{
            manifest.assetsFor('macos').single.id: digest,
          },
        ),
      ),
      flush: true,
    );
  }

  Future<void> dispose() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }
}

Map<String, Object?> _pinnedManifest(String digest) {
  return <String, Object?>{
    'schemaVersion': 1,
    'noticeDirectory': 'notices',
    'assets': <Object?>[
      <String, Object?>{
        'id': 'scrcpy-server',
        'version': '4.0',
        'platforms': <String>['macos'],
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
  };
}

Map<String, Object?> _derivedManifest() {
  final placeholder = List<String>.filled(64, '1').join();
  return <String, Object?>{
    'schemaVersion': 1,
    'noticeDirectory': 'notices',
    'assets': <Object?>[
      <String, Object?>{
        'id': 'serve-sim',
        'version': '0.1.40',
        'platforms': <String>['macos'],
        'sourceUrl': 'https://example.invalid/serve-sim-source.tgz',
        'sourceSha256': placeholder,
        'sourceCommit': '0123456789abcdef0123456789abcdef01234567',
        'payloadSha256': null,
        'relativePath': 'ios/serve-sim/0.1.40/serve-sim-bin',
        'archiveMember': null,
        'executable': true,
        'license': 'Apache-2.0',
        'licensePath': 'licenses/Apache-2.0.txt',
        'derivation': <String, Object?>{
          'type': 'swift-package',
          'sourceArchiveRoot': 'serve-sim-source',
          'sourceSubdirectory': 'packages/serve-sim',
          'packageDirectory': 'packages/serve-sim',
          'product': 'serve-sim-bin',
          'buildOutput': 'apple/Products/Release/serve-sim-bin',
          'architectures': <String>['arm64', 'x86_64'],
          'dependencyLockPath': 'packages/serve-sim/Package.resolved',
          'dependencyLockSha256': placeholder,
          'patchPath': 'patches/serve-sim.patch',
          'patchSha256': placeholder,
          'patchTargets': <Object?>[
            <String, Object?>{
              'path': 'packages/serve-sim/Package.swift',
              'beforeSha256': placeholder,
              'afterSha256': placeholder,
            },
          ],
          'dependencies': <Object?>[
            <String, Object?>{
              'id': 'swifter',
              'sourceUrl': 'https://example.invalid/swifter.tgz',
              'sourceSha256': placeholder,
              'sourceCommit': 'fedcba9876543210fedcba9876543210fedcba98',
              'archiveRoot': 'swifter-source',
              'destination': 'packages/swifter',
              'license': 'BSD-3-Clause',
              'licensePath': 'licenses/BSD-3-Clause.txt',
            },
          ],
        },
      },
    ],
  };
}
