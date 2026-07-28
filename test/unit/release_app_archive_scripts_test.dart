import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
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
    test('packages the system browser engines required by desktop tabs', () {
      final setup = File(
        '.github/actions/setup-flutter-workspace/action.yml',
      ).readAsStringSync();
      final linuxPackage = File(
        'tool/release/package_linux.sh',
      ).readAsStringSync();
      final podfile = File('macos/Podfile').readAsStringSync();
      final xcodeProject = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final macInfo = File('macos/Runner/Info.plist').readAsStringSync();
      final windowsBrowserCmake = File(
        'packages/alera_browser/windows/CMakeLists.txt',
      ).readAsStringSync();
      final windowsBrowserValues = File(
        'packages/alera_browser/windows/browser_value.cpp',
      ).readAsStringSync();
      final macBrowserCore = File(
        'packages/alera_browser/macos/Classes/BrowserCore.swift',
      ).readAsStringSync();

      expect(setup, contains('libwebkit2gtk-4.1-dev'));
      expect(linuxPackage, contains('libwebkit2gtk-4.1-0'));
      expect(linuxPackage, contains('libjson-glib-1.0-0'));
      expect(linuxPackage, contains('libsecret-1-0'));
      expect(linuxPackage, contains('libsqlite3-0'));
      expect(linuxPackage, contains('libssl3'));
      expect(linuxPackage, contains('Requires: webkit2gtk4.1'));
      expect(linuxPackage, contains('Requires: json-glib'));
      expect(linuxPackage, contains('Requires: libsecret'));
      expect(linuxPackage, contains('Requires: sqlite'));
      expect(linuxPackage, contains('Requires: openssl-libs'));
      expect(podfile, contains("platform :osx, '14.0'"));
      expect(xcodeProject, isNot(contains('MACOSX_DEPLOYMENT_TARGET = 10.15')));
      expect(xcodeProject, contains('MACOSX_DEPLOYMENT_TARGET = 14.0'));
      expect(macInfo, contains('NSCameraUsageDescription'));
      expect(macInfo, contains('NSLocationUsageDescription'));
      expect(macInfo, contains('NSMicrophoneUsageDescription'));
      expect(windowsBrowserCmake, contains('ALERA_BROWSER_STORAGE_NAME'));
      expect(windowsBrowserValues, contains('ALERA_BROWSER_STORAGE_NAME'));
      expect(macBrowserCore, contains('Bundle.main.bundleIdentifier'));
    });

    test('gates stable autonomous updates on platform trust credentials', () {
      final workflow = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();

      expect(
        workflow,
        contains(
          '--dart-define "ALERA_UPDATE_AUTO_INSTALL_ENABLED=\$auto_install_enabled"',
        ),
      );
      expect(workflow, contains('APPLE_DEVELOPER_ID_APPLICATION'));
      expect(workflow, contains('WINDOWS_CERTIFICATE_PFX_BASE64'));
      expect(workflow, contains('ALERA_LINUX_GPG_PRIVATE_KEY_BASE64'));
      expect(
        workflow,
        isNot(
          contains('--dart-define "ALERA_UPDATE_AUTO_INSTALL_ENABLED=false"'),
        ),
      );
    });

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
      final items = (manifest['items'] as List).cast<Map>();
      expect(items, hasLength(6));
      expect(
        items.map((item) => '${item['platform']}/${item['arch']}'),
        containsAll(<String>[
          'macos/x64',
          'macos/arm64',
          'windows/x64',
          'windows/arm64',
          'linux/x64',
          'linux/arm64',
        ]),
      );
      for (final item in items) {
        expect(item['artifactName'], startsWith('alera-runtime-1.2.3-'));
        expect(item['url'], contains('/releases/download/v1.2.3/'));
        expect(item, contains('sha256'));
        expect(item, contains('size'));
      }
    });

    test('builds and verifies RC manifests with Linux packages', () async {
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
        'alera-1.2.3-rc.0-linux.deb',
      );
      _writeArtifact(
        temp,
        'rc',
        '1.2.3+99-linux',
        'alera-1.2.3-rc.0-linux.rpm',
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
        items
            .cast<Map>()
            .where((item) => item['platform'] == 'linux')
            .map((item) => item['installerKind']),
        containsAll(<String>['deb', 'rpm']),
      );
      _expectLegacyArchiveShape(manifest);
    });

    test('rejects Linux desktop tarballs in signed manifests', () async {
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
      final keys = await _signingKeys(seed: 7);

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
      final verification = await Process.run(
        'dart',
        <String>['tool/release/verify_app_archive.dart', output],
        workingDirectory: Directory.current.path,
        environment: <String, String>{
          'ALERA_UPDATE_MANIFEST_PUBLIC_KEY': keys.publicKey,
        },
      );

      expect(verification.exitCode, isNot(0));
      expect(
        verification.stderr,
        contains('Linux desktop artifacts must be deb or rpm packages'),
      );
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
