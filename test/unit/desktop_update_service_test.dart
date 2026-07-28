import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_handoff.dart';
import 'package:alera/src/features/updater/infra/desktop_update_service.dart';
import 'package:alera/src/features/updater/infra/desktop_update_stager.dart';
import 'package:alera/src/features/updater/infra/update_manifest_signature.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  group('DesktopAleraUpdateService', () {
    test('returns an informational message on unsupported platforms', () async {
      final service = DesktopAleraUpdateService(platform: 'android');

      final result = await service.checkForUpdates();

      expect(result.latest, isNull);
      expect(result.message, 'Desktop updates are not available on android.');
    });

    test(
      'verifies signed manifests and enables trusted tarball updates',
      () async {
        final signed = await _signedArchive(<Map<String, Object?>>[
          _archiveItem(platform: 'macos', installerKind: 'tar.gz'),
        ]);
        final service = DesktopAleraUpdateService(
          config: _config(
            autoInstallEnabled: true,
            signedRelease: true,
            manifestPublicKey: signed.publicKey,
          ),
          client: MockClient((_) async => http.Response(signed.manifest, 200)),
          loadPackageInfo: () async => _packageInfo('1'),
          platform: 'macos',
        );

        final result = await service.checkForUpdates();

        expect(result.latest?.installerKind, 'tar.gz');
        expect(result.autoInstallAllowed, isTrue);
        expect(result.message, 'Update 1.2.3 is ready to install.');
      },
    );

    for (final installerKind in <String>['deb', 'rpm']) {
      test('selects the Linux $installerKind artifact', () async {
        final stager = _FakeStager();
        final service = DesktopAleraUpdateService(
          config: _config(
            channel: AleraUpdateChannel.rc,
            autoInstallEnabled: true,
          ),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(
                _archive(<Map<String, Object?>>[
                  _archiveItem(
                    platform: 'linux',
                    installerKind: 'deb',
                    version: '1.2.3-rc.0',
                  ),
                  _archiveItem(
                    platform: 'linux',
                    installerKind: 'rpm',
                    version: '1.2.3-rc.0',
                  ),
                ]),
              ),
              200,
            ),
          ),
          loadPackageInfo: () async => _packageInfo('1'),
          loadArtifactPreferences: (_, _) async => <String>[installerKind],
          stager: stager,
          platform: 'linux',
        );

        final result = await service.checkForUpdates();

        expect(result.latest?.installerKind, installerKind);
        expect(result.autoInstallAllowed, isFalse);
        expect(
          result.message,
          'Update 1.2.3-rc.0 is available for manual download.',
        );
        await expectLater(
          service.installUpdate(
            _update(platform: 'linux', installerKind: installerKind),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('apt, dnf'),
            ),
          ),
        );
        expect(stager.update, isNull);
      });
    }

    test(
      'keeps legacy Linux tarballs off the automatic install path',
      () async {
        final signed = await _signedArchive(<Map<String, Object?>>[
          _archiveItem(platform: 'linux', installerKind: 'tar.gz'),
        ]);
        final stager = _FakeStager();
        final service = DesktopAleraUpdateService(
          config: _config(
            channel: AleraUpdateChannel.rc,
            autoInstallEnabled: true,
            signedRelease: true,
            manifestPublicKey: signed.publicKey,
          ),
          client: MockClient((_) async => http.Response(signed.manifest, 200)),
          loadPackageInfo: () async => _packageInfo('1'),
          loadArtifactPreferences: (_, _) async => const <String>['tar.gz'],
          stager: stager,
          platform: 'linux',
        );

        final result = await service.checkForUpdates();

        expect(result.latest?.installerKind, 'tar.gz');
        expect(result.autoInstallAllowed, isFalse);
        expect(
          result.message,
          'Linux tarball updates are unsupported. Install the deb or rpm '
          'package through apt, dnf, or the configured package repository.',
        );
        await expectLater(
          service.installUpdate(
            _update(platform: 'linux', installerKind: 'tar.gz'),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('apt, dnf'),
            ),
          ),
        );
        expect(stager.update, isNull);
      },
    );

    test('reports when no compatible Linux package is published', () async {
      final service = DesktopAleraUpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              _archive(<Map<String, Object?>>[
                _archiveItem(platform: 'linux', installerKind: 'deb'),
              ]),
            ),
            200,
          ),
        ),
        loadPackageInfo: () async => _packageInfo('1'),
        loadArtifactPreferences: (_, _) async => const <String>[],
        platform: 'linux',
      );

      final result = await service.checkForUpdates();

      expect(result.latest, isNull);
      expect(
        result.message,
        'No compatible Linux package is available for this distribution. '
        'Install Alera through apt, dnf, or a supported package repository.',
      );
    });

    test('keeps legacy artifacts on the manual download path', () async {
      final service = DesktopAleraUpdateService(
        config: _config(
          channel: AleraUpdateChannel.rc,
          autoInstallEnabled: true,
        ),
        client: MockClient((_) async => http.Response(_legacyArchive, 200)),
        loadPackageInfo: () async => _packageInfo('1'),
        loadArtifactPreferences: (_, _) async => const <String>['directory'],
        platform: 'macos',
      );

      final result = await service.checkForUpdates();

      expect(result.latest, isNotNull);
      expect(result.autoInstallAllowed, isFalse);
      expect(
        result.message,
        'Automatic installation requires a signed update artifact with integrity metadata.',
      );
    });

    test(
      'handles missing indexes, current builds, and HTTP failures',
      () async {
        final notPublished = DesktopAleraUpdateService(
          client: MockClient((_) async => http.Response('', 404)),
          platform: 'macos',
        );
        final current = DesktopAleraUpdateService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(
                _archive(<Map<String, Object?>>[
                  _archiveItem(platform: 'macos', installerKind: 'tar.gz'),
                ]),
              ),
              200,
            ),
          ),
          loadPackageInfo: () async => _packageInfo('2'),
          platform: 'macos',
        );
        final failed = DesktopAleraUpdateService(
          client: MockClient((_) async => http.Response('boom', 500)),
          platform: 'macos',
        );

        expect(
          (await notPublished.checkForUpdates()).message,
          'No update index is published yet.',
        );
        expect(
          (await current.checkForUpdates()).message,
          'Alera is up to date.',
        );
        await expectLater(
          failed.checkForUpdates(),
          throwsA(isA<HttpException>()),
        );
      },
    );

    test('stages, reports progress, and hands off a verified update', () async {
      final stager = _FakeStager();
      final handoff = _FakeHandoff();
      final service = DesktopAleraUpdateService(
        config: _config(
          channel: AleraUpdateChannel.rc,
          autoInstallEnabled: true,
        ),
        stager: stager,
        handoff: handoff,
        platform: 'macos',
      );
      final update = _update();
      final progress = <double>[];

      await service.installUpdate(update, onProgress: progress.add);
      await service.restartApp();

      expect(stager.update, same(update));
      expect(progress, <double>[0.5, 1]);
      expect(handoff.stagedUpdate?.update, same(update));
    });

    test('rejects automatic install when the build disables it', () async {
      final service = DesktopAleraUpdateService(
        config: _config(),
        stager: _FakeStager(),
        handoff: _FakeHandoff(),
        platform: 'macos',
      );

      await expectLater(service.installUpdate(_update()), throwsStateError);
      await expectLater(service.restartApp(), throwsStateError);
    });

    test('opens release pages and reports launcher refusal', () async {
      final launched = <Uri>[];
      final service = DesktopAleraUpdateService(
        config: _config(
          releasePageUrl: Uri.parse(
            'https://github.com/leynier/alera/releases/tag/v1.0.0',
          ),
        ),
        launchUrl: (uri) async {
          launched.add(uri);
          return true;
        },
        platform: 'windows',
      );
      final refused = DesktopAleraUpdateService(
        config: _config(),
        launchUrl: (_) async => false,
        platform: 'windows',
      );

      await service.openDownloadPage(_update(version: '1.2.3'));

      expect(
        launched.single,
        Uri.parse('https://github.com/leynier/alera/releases/tag/v1.2.3'),
      );
      await expectLater(refused.openDownloadPage(null), throwsStateError);
    });

    test('uses the default url launcher delegate', () async {
      final previousPlatform = UrlLauncherPlatform.instance;
      final fakePlatform = _FakeUrlLauncherPlatform();
      UrlLauncherPlatform.instance = fakePlatform;
      addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);
      final service = DesktopAleraUpdateService(
        config: _config(),
        platform: 'macos',
      );
      addTearDown(service.dispose);

      await service.openDownloadPage(null);

      expect(fakePlatform.launchedUrls, <String>[
        'https://example.com/releases',
      ]);
    });
  });
}

class _FakeStager implements AleraDesktopUpdateStager {
  AleraUpdateInfo? update;

  @override
  Future<StagedDesktopUpdate> stage(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    this.update = update;
    onProgress?.call(0.5);
    onProgress?.call(1);
    final directory = await Directory.systemTemp.createTemp('service-test-');
    return StagedDesktopUpdate(
      update: update,
      directory: directory,
      artifactPath: '${directory.path}/artifact',
      payloadPath: '${directory.path}/payload',
    );
  }
}

class _FakeHandoff implements AleraDesktopUpdateHandoff {
  StagedDesktopUpdate? stagedUpdate;

  @override
  Future<void> applyAndRestart(StagedDesktopUpdate stagedUpdate) async {
    this.stagedUpdate = stagedUpdate;
    await stagedUpdate.delete();
  }
}

class _FakeUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launchedUrls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    return true;
  }
}

AleraUpdateConfig _config({
  Uri? releasePageUrl,
  AleraUpdateChannel channel = AleraUpdateChannel.stable,
  bool autoInstallEnabled = false,
  bool signedRelease = false,
  String manifestPublicKey = '',
}) {
  return AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/archive.json'),
    releasePageUrl: releasePageUrl ?? Uri.parse('https://example.com/releases'),
    channel: channel,
    autoInstallEnabled: autoInstallEnabled,
    signedRelease: signedRelease,
    manifestPublicKey: manifestPublicKey,
  );
}

AleraUpdateInfo _update({
  String version = '1.2.3',
  String platform = 'macos',
  String installerKind = 'tar.gz',
}) {
  return AleraUpdateInfo(
    version: version,
    shortVersion: 2,
    date: '2026-07-27',
    mandatory: false,
    url: Uri.parse('https://example.com/alera.$installerKind'),
    platform: platform,
    changes: const <String>['Update Alera'],
    installerKind: installerKind,
    sha256: _sha256,
    size: 42,
  );
}

PackageInfo _packageInfo(String buildNumber) {
  return PackageInfo(
    appName: 'Alera',
    packageName: 'dev.leynier.alera',
    version: '1.0.0',
    buildNumber: buildNumber,
  );
}

Map<String, Object?> _archive(List<Map<String, Object?>> items) {
  return <String, Object?>{
    'schemaVersion': 2,
    'appName': 'Alera',
    'items': items,
  };
}

Map<String, Object?> _archiveItem({
  required String platform,
  required String installerKind,
  String version = '1.2.3',
}) {
  return <String, Object?>{
    'version': version,
    'shortVersion': 2,
    'date': '2026-07-27',
    'mandatory': false,
    'changes': const <Object?>[],
    'platform': platform,
    'installerKind': installerKind,
    'url': 'https://example.com/alera.$installerKind',
    'sha256': _sha256,
    'size': 42,
  };
}

Future<({String manifest, String publicKey})> _signedArchive(
  List<Map<String, Object?>> items,
) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 9));
  final keyData = await keyPair.extract();
  final publicKeyData = await keyPair.extractPublicKey();
  final privateKey = base64Encode(keyData.bytes);
  final publicKey = base64Encode(publicKeyData.bytes);
  final signed = await signAleraManifest(
    manifest: _archive(items),
    privateKeyBase64: privateKey,
    publicKeyBase64: publicKey,
    publicKeyId: 'test-key',
  );
  return (manifest: jsonEncode(signed), publicKey: publicKey);
}

const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const String _legacyArchive = '''
{
  "appName": "Alera",
  "items": [
    {
      "version": "1.2.3-rc.0",
      "shortVersion": 2,
      "date": "2026-07-27",
      "mandatory": false,
      "changes": [],
      "platform": "macos",
      "url": "https://example.com/update-directory"
    }
  ]
}
''';
