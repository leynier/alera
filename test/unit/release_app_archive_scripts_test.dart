import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/latest_stable_release.dart' as latest_stable;

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
          '',
        ]),
        '0.1.0',
      );
    });
  });

  group('release archive scripts', () {
    test(
      'builds and verifies a stable manifest without sidecar URLs',
      () async {
        final temp = await Directory.systemTemp.createTemp('alera-release-');
        addTearDown(() => temp.deleteSync(recursive: true));
        _writeArtifact(
          temp,
          'stable',
          '1.2.3+99-macos',
          'alera-1.2.3-macos.tar.gz',
        );
        _writeArtifact(
          temp,
          'stable',
          '1.2.3+99-macos',
          'alera-runtime-1.2.3-macos-x64.tar.gz',
        );
        _writeArtifact(
          temp,
          'stable',
          '1.2.3+99-windows',
          'alera-1.2.3-windows.tar.gz',
        );
        _writeArtifact(
          temp,
          'stable',
          '1.2.3+99-windows',
          'alera-runtime-1.2.3-windows-x64.tar.gz',
        );
        _writeArtifact(
          temp,
          'stable',
          '1.2.3+99-linux',
          'alera-1.2.3-linux.deb',
        );
        _writeArtifact(
          temp,
          'stable',
          '1.2.3+99-linux',
          'alera-1.2.3-linux.rpm',
        );
        _writeArtifact(
          temp,
          'stable',
          '1.2.3+99-linux',
          'alera-runtime-1.2.3-linux-x64.tar.gz',
        );
        final output = p.join(temp.path, 'public', 'app-archive.json');
        final keys = await _signingKeys(seed: 4);

        await _runDartScript(
          'tool/release/build_app_archive.dart',
          <String>[output],
          environment: _archiveEnvironment(temp, channel: 'stable'),
        );
        await _runDartScript('tool/release/sign_app_archive.dart', <String>[
          output,
        ], environment: keys.toEnvironment());
        await _runDartScript(
          'tool/release/verify_app_archive.dart',
          <String>[output],
          environment: <String, String>{
            'ALERA_UPDATE_MANIFEST_PUBLIC_KEY': keys.publicKey,
          },
        );

        final manifest = jsonDecode(File(output).readAsStringSync()) as Map;
        final items = manifest['items'] as List;
        expect(items, hasLength(4));
        expect(
          items.cast<Map>().map((item) => item['url'] as String),
          isNot(contains(contains('alera-runtime-'))),
        );
        for (final item in items.cast<Map>()) {
          expect(item, contains('url'));
          expect(item, contains('platform'));
          expect(item, contains('installerKind'));
          expect(item, contains('sha256'));
          expect(item, contains('size'));
          expect(item, isNot(contains('artifacts')));
          expect(item, isNot(contains('signatureBundleUrl')));
          expect(item, isNot(contains('provenanceUrl')));
        }
        _expectLegacyArchiveShape(manifest);
      },
    );

    test('verifies rc manifests without Linux packages', () async {
      final temp = await Directory.systemTemp.createTemp('alera-release-');
      addTearDown(() => temp.deleteSync(recursive: true));
      _writeArtifact(
        temp,
        'rc',
        '1.2.3+99-macos',
        'alera-1.2.3-rc.0-macos.tar.gz',
      );
      _writeArtifact(
        temp,
        'rc',
        '1.2.3+99-windows',
        'alera-1.2.3-rc.0-windows.tar.gz',
      );
      _writeArtifact(
        temp,
        'rc',
        '1.2.3+99-linux',
        'alera-1.2.3-rc.0-linux.tar.gz',
      );
      final output = p.join(temp.path, 'public', 'app-archive-rc.json');
      final keys = await _signingKeys(seed: 5);

      await _runDartScript(
        'tool/release/build_app_archive.dart',
        <String>[output],
        environment: _archiveEnvironment(
          temp,
          channel: 'rc',
          releaseVersion: '1.2.3-rc.0',
        ),
      );
      await _runDartScript('tool/release/sign_app_archive.dart', <String>[
        output,
      ], environment: keys.toEnvironment());
      await _runDartScript(
        'tool/release/verify_app_archive.dart',
        <String>[output],
        environment: <String, String>{
          'ALERA_UPDATE_MANIFEST_PUBLIC_KEY': keys.publicKey,
        },
      );

      final manifest = jsonDecode(File(output).readAsStringSync()) as Map;
      expect(manifest['channel'], 'rc');
      final items = manifest['items'] as List;
      expect(
        items.cast<Map>().where((item) => item['platform'] == 'linux'),
        contains(predicate<Map>((item) => item['installerKind'] == 'tar.gz')),
      );
      _expectLegacyArchiveShape(manifest);
    });
  });
}

void _expectLegacyArchiveShape(Map<Object?, Object?> manifest) {
  final items = manifest['items'];
  expect(items, isA<List>());
  for (final item in (items! as List).cast<Map>()) {
    expect(item['version'], isA<String>());
    expect(item['shortVersion'], isA<int>());
    expect(item['changes'], isA<List>());
    expect(item['date'], isA<String>());
    expect(item['mandatory'], isA<bool>());
    expect(item['url'], isA<String>());
    expect(item['platform'], isA<String>());
  }
}

Map<String, String> _archiveEnvironment(
  Directory temp, {
  required String channel,
  String releaseVersion = '1.2.3',
}) {
  return <String, String>{
    'ALERA_RELEASE_VERSION': releaseVersion,
    'ALERA_ARTIFACT_VERSION': '1.2.3',
    'ALERA_RELEASE_BUILD_NUMBER': '99',
    'ALERA_UPDATE_BASE_URL': 'https://updates.example.test',
    'ALERA_UPDATE_PATH_PREFIX': 'updates/$channel',
    'ALERA_RELEASE_PUBLIC_DIR': p.join(temp.path, 'public'),
  };
}

void _writeArtifact(
  Directory temp,
  String channel,
  String folder,
  String name,
) {
  final file = File(
    p.join(temp.path, 'public', 'updates', channel, folder, name),
  );
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
      '$script failed with ${result.exitCode}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
  }
}

Future<_SigningKeys> _signingKeys({required int seed}) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(List.filled(32, seed));
  final keyData = await keyPair.extract();
  final publicKeyData = await keyPair.extractPublicKey();
  return _SigningKeys(
    privateKey: base64Encode(keyData.bytes),
    publicKey: base64Encode(publicKeyData.bytes),
  );
}

class _SigningKeys {
  const _SigningKeys({required this.privateKey, required this.publicKey});

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
