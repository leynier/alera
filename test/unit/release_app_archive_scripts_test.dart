import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/latest_stable_release.dart' as latest_stable;
import '../../tool/release/update_mobile_pubspec_version.dart'
    as mobile_version;

void main() {
  group('latest stable release script', () {
    test(
      'selects the semver maximum stable tag and ignores release candidates',
      () {
        expect(
          latest_stable.latestStableRelease(<String>[
            'v1.4.9',
            'v1.4.10-rc.0',
            'v1.4.10',
            'v1.10.0',
            'v2.0.0-rc.1',
            'not-a-version',
          ]),
          '1.10.0',
        );
      },
    );

    test('falls back when no stable release tags exist', () {
      expect(
        latest_stable.latestStableRelease(<String>[
          'v1.0.0-rc.0',
          'mobile-v0.0.12',
          'v0.0.12-mobile',
          'v0.0.12-rc.1-mobile',
          '',
        ]),
        '0.1.0',
      );
    });
  });

  group('mobile release version script', () {
    test('updates only the mobile pubspec version', () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-mobile-version-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final pubspec = File(p.join(temp.path, 'pubspec.yaml'))
        ..writeAsStringSync(
          'name: alera_mobile\nversion: 0.0.1+1\nenvironment:\n  sdk: ^3.12.2\n',
        );

      mobile_version.updateMobilePubspecVersion(
        '1.2.3',
        45,
        pubspecPath: pubspec.path,
      );

      expect(pubspec.readAsStringSync(), contains('version: 1.2.3+45'));
      expect(pubspec.readAsStringSync(), contains('name: alera_mobile'));
    });
  });

  group('release archive scripts', () {
    test('merges and verifies a signed schema 3 desktop channel', () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-desktop-release-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final keys = await _signingKeys(seed: 4);
      await _writeDesktopChannelFixture(temp, keys: keys);
      final archive = p.join(
        temp.path,
        'public',
        'updates',
        'stable',
        'app-archive.json',
      );

      await _runDartScript(
        'tool/release/merge_desktop_update_indexes.dart',
        <String>[
          p.join(temp.path, 'public', 'update-index-fragments'),
          archive,
        ],
      );
      await _runDartScript(
        'tool/release/verify_desktop_update_channel.dart',
        <String>[p.join(temp.path, 'public'), archive],
        environment: <String, String>{
          ...keys.toEnvironment(),
          'ALERA_RELEASE_CHANNEL': 'stable',
          'ALERA_RELEASE_VERSION': '1.2.3',
          'ALERA_RELEASE_BUILD_NUMBER': '99',
        },
      );

      final index =
          jsonDecode(File(archive).readAsStringSync()) as Map<String, dynamic>;
      expect(index['schemaVersion'], 3);
      final items = (index['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(3));
      expect(items.map((item) => item['platform']), <String>[
        'linux',
        'macos',
        'windows',
      ]);
      for (final item in items) {
        expect(item, contains('release'));
        expect(item, isNot(contains('url')));
        expect(item, isNot(contains('installerKind')));
      }
    });

    test('rejects a tampered schema 3 desktop artifact', () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-desktop-release-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final keys = await _signingKeys(seed: 5);
      final artifacts = await _writeDesktopChannelFixture(temp, keys: keys);
      final archive = p.join(
        temp.path,
        'public',
        'updates',
        'stable',
        'app-archive.json',
      );
      await _runDartScript(
        'tool/release/merge_desktop_update_indexes.dart',
        <String>[
          p.join(temp.path, 'public', 'update-index-fragments'),
          archive,
        ],
      );
      artifacts.first.writeAsStringSync('tampered');

      final verification = await Process.run(
        'dart',
        <String>[
          'tool/release/verify_desktop_update_channel.dart',
          p.join(temp.path, 'public'),
          archive,
        ],
        workingDirectory: Directory.current.path,
        environment: <String, String>{
          ...keys.toEnvironment(),
          'ALERA_RELEASE_CHANNEL': 'stable',
          'ALERA_RELEASE_VERSION': '1.2.3',
          'ALERA_RELEASE_BUILD_NUMBER': '99',
        },
      );

      expect(verification.exitCode, isNot(0));
      expect(verification.stderr, contains('has length'));
    });

    test('builds and verifies a signed runtime archive', () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-runtime-release-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      _writeReleaseAsset(temp, 'alera-runtime-1.2.3-macos-x64.tar.gz');
      _writeReleaseAsset(temp, 'alera-runtime-1.2.3-macos-arm64.tar.gz');
      _writeReleaseAsset(temp, 'alera-runtime-1.2.3-windows-x64.tar.gz');
      _writeReleaseAsset(temp, 'alera-runtime-1.2.3-windows-arm64.tar.gz');
      _writeReleaseAsset(temp, 'alera-runtime-1.2.3-linux-x64.tar.gz');
      _writeReleaseAsset(temp, 'alera-runtime-1.2.3-linux-arm64.tar.gz');
      final output = p.join(temp.path, 'public', 'runtime-archive.json');
      final keys = await _signingKeys(seed: 6);

      await _runDartScript(
        'tool/release/build_runtime_archive.dart',
        <String>[output],
        environment: <String, String>{
          'ALERA_RELEASE_VERSION': '1.2.3',
          'ALERA_RELEASE_BUILD_NUMBER': '99',
          'ALERA_RELEASE_CHANNEL': 'stable',
          'ALERA_RELEASE_ASSETS_DIR': p.join(temp.path, 'release-assets'),
          'ALERA_RUNTIME_RELEASE_BASE_URL':
              'https://github.com/example/alera/releases/download/v1.2.3',
        },
      );
      await _runDartScript('tool/release/sign_app_archive.dart', <String>[
        output,
      ], environment: keys.toEnvironment());
      await _runDartScript(
        'tool/release/verify_runtime_archive.dart',
        <String>[output],
        environment: <String, String>{
          'ALERA_UPDATE_MANIFEST_PUBLIC_KEY': keys.publicKey,
        },
      );

      final manifest = jsonDecode(File(output).readAsStringSync()) as Map;
      expect(manifest['schemaVersion'], 1);
      expect(manifest['channel'], 'stable');
      expect(manifest['items'], hasLength(6));
    });
  });
}

Future<List<File>> _writeDesktopChannelFixture(
  Directory temp, {
  required _SigningKeys keys,
}) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(keys.seed);
  final publicRoot = Directory(p.join(temp.path, 'public'));
  final fragments = Directory(p.join(publicRoot.path, 'update-index-fragments'))
    ..createSync(recursive: true);
  final artifacts = <File>[];
  for (final platform in const <String>['linux', 'macos', 'windows']) {
    final releaseDirectory = Directory(
      p.join(
        publicRoot.path,
        'updates',
        'stable',
        'releases',
        '1.2.3',
        platform,
      ),
    )..createSync(recursive: true);
    final artifact = File(
      p.join(releaseDirectory.path, 'Alera-1.2.3-$platform.zip'),
    )..writeAsStringSync('desktop-update-$platform');
    artifacts.add(artifact);
    final descriptor = ReleaseDescriptor.fromJson(<String, dynamic>{
      'schemaVersion': 3,
      'packageId': 'dev.leynier.alera',
      'appName': 'Alera',
      'version': '1.2.3',
      'buildNumber': 99,
      'platform': platform,
      'channel': 'stable',
      'artifact': <String, dynamic>{
        'kind': 'zip',
        'url':
            'https://updates.alera.build/updates/stable/releases/1.2.3/'
            '$platform/${p.basename(artifact.path)}',
        'sha256': sha256.convert(artifact.readAsBytesSync()).toString(),
        'length': artifact.lengthSync(),
      },
      'install': <String, dynamic>{
        'strategy': platform == 'macos'
            ? 'wholeBundleReplace'
            : 'wholeDirectoryReplace',
      },
      'minimumUpdaterVersion': '2.5.0',
      'generatedAt': '2026-07-27T00:00:00.000Z',
      'signature': <String, dynamic>{
        'algorithm': 'ed25519',
        'publicKeyId': 'test-key',
        'value': '',
      },
    });
    final signature = await Ed25519().sign(
      descriptor.canonicalSignatureBytes(),
      keyPair: keyPair,
    );
    final descriptorJson = descriptor.toJson();
    descriptorJson['signature'] = <String, dynamic>{
      'algorithm': 'ed25519',
      'publicKeyId': 'test-key',
      'value': base64Encode(signature.bytes),
    };
    File(
      p.join(releaseDirectory.path, 'release.json'),
    ).writeAsStringSync(jsonEncode(descriptorJson));
    File(p.join(fragments.path, '$platform.json')).writeAsStringSync(
      jsonEncode(<String, dynamic>{
        'schemaVersion': 3,
        'appName': 'Alera',
        'items': <Object?>[
          <String, dynamic>{
            'version': '1.2.3',
            'buildNumber': 99,
            'platform': platform,
            'channel': 'stable',
            'mandatory': false,
            'release':
                'https://updates.alera.build/updates/stable/releases/1.2.3/'
                '$platform/release.json',
          },
        ],
      }),
    );
  }
  return artifacts;
}

void _writeReleaseAsset(Directory temp, String name) {
  final file = File(p.join(temp.path, 'release-assets', name));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(name);
}

Future<void> _runDartScript(
  String script,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    'dart',
    <String>[script, ...args],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
  if (result.exitCode != 0) {
    fail(
      '$script failed with ${result.exitCode}\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }
}

Future<_SigningKeys> _signingKeys({required int seed}) async {
  final seedBytes = List<int>.filled(32, seed);
  final keyPair = await Ed25519().newKeyPairFromSeed(seedBytes);
  final keyData = await keyPair.extract();
  final publicKeyData = await keyPair.extractPublicKey();
  return _SigningKeys(
    seed: seedBytes,
    privateKey: base64Encode(keyData.bytes),
    publicKey: base64Encode(publicKeyData.bytes),
  );
}

class _SigningKeys {
  const _SigningKeys({
    required this.seed,
    required this.privateKey,
    required this.publicKey,
  });

  final List<int> seed;
  final String privateKey;
  final String publicKey;

  Map<String, String> toEnvironment() {
    return <String, String>{
      'ALERA_UPDATE_MANIFEST_PRIVATE_KEY': privateKey,
      'ALERA_UPDATE_MANIFEST_PUBLIC_KEY': publicKey,
      'ALERA_UPDATE_MANIFEST_PUBLIC_KEY_ID': 'test-key',
    };
  }
}
