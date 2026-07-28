import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/native_helpers/native_helper_manifest.dart';
import '../../tool/native_helpers/native_helper_materializer.dart';

void main() {
  test(
    'rederives a source-built helper after payload and manifest tampering',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-native-helper-derivation-trust-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final repository = Directory(p.join(temp.path, 'repository'))
        ..createSync(recursive: true);
      final notices = Directory(p.join(repository.path, 'notices', 'licenses'))
        ..createSync(recursive: true);
      File(
        p.join(repository.path, 'notices', 'NOTICE.md'),
      ).writeAsStringSync('Test notices.\n');
      for (final license in <String>['Apache-2.0.txt', 'BSD-3-Clause.txt']) {
        File(
          p.join(notices.path, license),
        ).writeAsStringSync('Test license.\n');
      }

      final source = utf8.encode('pinned source');
      final manifestFile = File(p.join(repository.path, 'manifest.json'))
        ..writeAsStringSync(
          jsonEncode(
            _derivedManifest(sourceSha256: sha256.convert(source).toString()),
          ),
        );
      final manifest = NativeHelperManifest.read(manifestFile);
      var downloads = 0;
      var derivations = 0;
      final materializer = NativeHelperMaterializer(
        repositoryRoot: repository,
        manifest: manifest,
        downloader: (_, output) async {
          downloads += 1;
          await output.writeAsBytes(source, flush: true);
        },
        derivedPayloadBuilder:
            ({
              required asset,
              required derivation,
              required source,
              required cache,
              required offline,
            }) async {
              derivations += 1;
              return Uint8List.fromList(utf8.encode('derived-$derivations'));
            },
      );
      final output = Directory(p.join(temp.path, 'prepared'));
      final cache = Directory(p.join(temp.path, 'cache'));

      await materializer.prepare(
        platform: 'macos',
        output: output,
        cache: cache,
      );
      expect(downloads, 1);
      expect(derivations, 1);

      final payload = File(
        p.join(output.path, 'ios', 'serve-sim', '0.1.40', 'serve-sim-bin'),
      );
      final tampered = utf8.encode('tampered payload');
      payload.writeAsBytesSync(tampered);
      final generatedManifest = File(p.join(output.path, 'manifest.json'));
      final generated =
          jsonDecode(generatedManifest.readAsStringSync())
              as Map<String, Object?>;
      final generatedAsset =
          (generated['assets']! as List<Object?>).single
              as Map<String, Object?>;
      generatedAsset['sha256'] = sha256.convert(tampered).toString();
      generatedManifest.writeAsStringSync(jsonEncode(generated));

      // This pair is internally consistent, but it is not a trust anchor for a
      // source-derived payload. Preparation must still rebuild it.
      await verifyNativeHelperBundle(
        platform: 'macos',
        emulatorRoot: output,
        expected: manifest,
      );
      await materializer.prepare(
        platform: 'macos',
        output: output,
        cache: cache,
        offline: true,
      );

      expect(downloads, 1);
      expect(derivations, 2);
      expect(payload.readAsStringSync(), 'derived-2');
      await verifyNativeHelperBundle(
        platform: 'macos',
        emulatorRoot: output,
        expected: manifest,
      );
    },
  );
}

Map<String, Object?> _derivedManifest({required String sourceSha256}) {
  final placeholderSha256 = List<String>.filled(64, '1').join();
  return <String, Object?>{
    'schemaVersion': 1,
    'noticeDirectory': 'notices',
    'assets': <Object?>[
      <String, Object?>{
        'id': 'serve-sim',
        'version': '0.1.40',
        'platforms': <String>['macos'],
        'sourceUrl': 'https://example.invalid/serve-sim-source.tgz',
        'sourceSha256': sourceSha256,
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
          'dependencyLockSha256': placeholderSha256,
          'patchPath': 'patches/serve-sim.patch',
          'patchSha256': placeholderSha256,
          'patchTargets': <Object?>[
            <String, Object?>{
              'path': 'packages/serve-sim/Package.swift',
              'beforeSha256': placeholderSha256,
              'afterSha256': placeholderSha256,
            },
          ],
          'dependencies': <Object?>[
            <String, Object?>{
              'id': 'swifter',
              'sourceUrl': 'https://example.invalid/swifter.tgz',
              'sourceSha256': placeholderSha256,
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
