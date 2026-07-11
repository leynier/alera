import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_service.dart';
import 'package:alera/src/features/updater/infra/update_manifest_signature.dart';
import 'package:cryptography/cryptography.dart';
import 'package:desktop_updater/desktop_updater.dart';
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

    test('uses the desktop updater when auto-install is allowed', () async {
      final updater = _FakeDesktopUpdater()
        ..versionCheckResult = _item(
          version: '0.1.4-rc.0',
          shortVersion: 4,
          url: 'https://example.com/updates/0.1.4+4-macos',
          platform: 'macos',
        );
      final service = DesktopAleraUpdateService(
        config: AleraUpdateConfig(
          archiveUrl: Uri.parse('https://example.com/archive.json'),
          releasePageUrl: Uri.parse('https://example.com/releases'),
          channel: AleraUpdateChannel.rc,
          autoInstallEnabled: true,
          signedRelease: false,
        ),
        desktopUpdater: updater,
        platform: 'macos',
      );

      final result = await service.checkForUpdates();

      expect(updater.checkedArchiveUrls, <String>[
        'https://example.com/archive.json',
      ]);
      expect(result.autoInstallAllowed, isTrue);
      expect(result.latest?.version, '0.1.4-rc.0');
      expect(result.message, 'Update 0.1.4-rc.0 is ready to install.');
    });

    test(
      'checks the published archive manually when auto-install is blocked',
      () async {
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive.json'),
            releasePageUrl: Uri.parse('https://example.com/releases'),
            channel: AleraUpdateChannel.stable,
            autoInstallEnabled: true,
            signedRelease: false,
          ),
          client: MockClient((request) async {
            expect(request.url.toString(), 'https://example.com/archive.json');
            return http.Response(_archiveJson, 200);
          }),
          loadPackageInfo: () async => _packageInfo(buildNumber: '1'),
          platform: 'macos',
        );

        final result = await service.checkForUpdates();

        expect(result.latest?.version, '0.1.2');
        expect(
          result.message,
          'Automatic installation is blocked until stable releases are signed.',
        );
      },
    );

    test(
      'manual checks describe downloadable updates when auto-install is off',
      () async {
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive.json'),
            releasePageUrl: Uri.parse('https://example.com/releases'),
            channel: AleraUpdateChannel.stable,
            autoInstallEnabled: false,
            signedRelease: false,
          ),
          client: MockClient((_) async => http.Response(_archiveJson, 200)),
          loadPackageInfo: () async => _packageInfo(buildNumber: '1'),
          platform: 'macos',
        );

        final result = await service.checkForUpdates();

        expect(
          result.message,
          'Update 0.1.2 is available for manual download.',
        );
      },
    );

    test(
      'returns friendly manual-update messages for 404 and no newer build',
      () async {
        final notPublished = DesktopAleraUpdateService(
          client: MockClient((_) async => http.Response('', 404)),
          platform: 'linux',
        );
        final upToDate = DesktopAleraUpdateService(
          client: MockClient((_) async => http.Response(_archiveJson, 200)),
          loadPackageInfo: () async => _packageInfo(buildNumber: '3'),
          platform: 'macos',
        );

        final notPublishedResult = await notPublished.checkForUpdates();
        final upToDateResult = await upToDate.checkForUpdates();

        expect(notPublishedResult.message, 'No update index is published yet.');
        expect(upToDateResult.message, 'Alera is up to date.');
      },
    );

    test(
      'verifies signed manifests and routes Linux updates through packages',
      () async {
        final signed = await _signedArchiveV2Json();
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive.json'),
            releasePageUrl: Uri.parse('https://example.com/releases'),
            channel: AleraUpdateChannel.stable,
            autoInstallEnabled: true,
            signedRelease: true,
            manifestPublicKey: signed.publicKey,
          ),
          client: MockClient((_) async => http.Response(signed.manifest, 200)),
          loadPackageInfo: () async => _packageInfo(buildNumber: '1'),
          platform: 'linux',
        );

        final result = await service.checkForUpdates();

        expect(result.latest?.version, '1.0.0');
        expect(result.latest?.installerKind, 'deb');
        expect(result.autoInstallAllowed, isFalse);
        expect(
          result.message,
          'Update 1.0.0 is available through the Linux package repository.',
        );
      },
    );

    test(
      'routes Linux release-candidate tarballs to manual download',
      () async {
        final signed = await _signedArchiveV2Json(
          channel: 'rc',
          version: '1.0.0-rc.0',
          installerKind: 'tar.gz',
          artifactUrl: 'https://example.com/alera-linux.tar.gz',
        );
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive-rc.json'),
            releasePageUrl: Uri.parse('https://example.com/releases'),
            channel: AleraUpdateChannel.rc,
            autoInstallEnabled: true,
            signedRelease: true,
            manifestPublicKey: signed.publicKey,
          ),
          client: MockClient((_) async => http.Response(signed.manifest, 200)),
          loadPackageInfo: () async => _packageInfo(buildNumber: '1'),
          platform: 'linux',
        );

        final result = await service.checkForUpdates();

        expect(result.latest?.version, '1.0.0-rc.0');
        expect(result.latest?.installerKind, 'tar.gz');
        expect(result.autoInstallAllowed, isFalse);
        expect(
          result.message,
          'Update 1.0.0-rc.0 is available for manual download.',
        );
      },
    );

    test(
      'throws when the archive download fails with a non-404 status',
      () async {
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive.json'),
            releasePageUrl: Uri.parse('https://example.com/releases'),
            channel: AleraUpdateChannel.stable,
            autoInstallEnabled: false,
            signedRelease: false,
          ),
          client: MockClient((_) async => http.Response('boom', 500)),
          platform: 'macos',
        );

        await expectLater(
          service.checkForUpdates(),
          throwsA(isA<HttpException>()),
        );
      },
    );

    test(
      'installs an available update and reports progress until completion',
      () async {
        final updater = _FakeDesktopUpdater()
          ..versionCheckResult = _item(
            version: '0.1.4-rc.0',
            shortVersion: 4,
            url: 'https://example.com/updates/0.1.4+4-macos',
            platform: 'macos',
            changedFiles: <FileHashModel?>[
              FileHashModel(
                filePath: 'Alera.app',
                calculatedHash: 'abc',
                length: 42,
              ),
            ],
          )
          ..updateStream = Stream<UpdateProgress>.fromIterable(<UpdateProgress>[
            UpdateProgress(
              totalBytes: 100,
              receivedBytes: 25,
              currentFile: 'Alera.app',
              totalFiles: 1,
              completedFiles: 0,
            ),
            UpdateProgress(
              totalBytes: 100,
              receivedBytes: 100,
              currentFile: 'Alera.app',
              totalFiles: 1,
              completedFiles: 1,
            ),
          ]);
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive.json'),
            releasePageUrl: Uri.parse('https://example.com/releases'),
            channel: AleraUpdateChannel.rc,
            autoInstallEnabled: true,
            signedRelease: false,
          ),
          desktopUpdater: updater,
          platform: 'macos',
        );
        final progress = <double>[];

        await service.installUpdate(
          AleraUpdateInfo(
            version: '0.1.4-rc.0',
            shortVersion: 4,
            date: '2026-05-25',
            mandatory: false,
            url: Uri.parse('https://example.com/updates/0.1.4+4-macos'),
            platform: 'macos',
            changes: <String>['Preview'],
          ),
          onProgress: progress.add,
        );

        expect(updater.updatedFolders, <String>[
          'https://example.com/updates/0.1.4+4-macos',
        ]);
        expect(updater.updatedChangedFiles.single, hasLength(1));
        expect(progress, <double>[0.25, 1, 1]);
      },
    );

    test('rejects installation when automatic updates are disabled', () async {
      final service = DesktopAleraUpdateService(
        config: AleraUpdateConfig(
          archiveUrl: Uri.parse('https://example.com/archive.json'),
          releasePageUrl: Uri.parse('https://example.com/releases'),
          channel: AleraUpdateChannel.stable,
          autoInstallEnabled: false,
          signedRelease: false,
        ),
        platform: 'macos',
      );

      await expectLater(
        service.installUpdate(
          AleraUpdateInfo(
            version: '0.1.2',
            shortVersion: 3,
            date: '2026-05-25',
            mandatory: false,
            url: Uri.parse('https://example.com/updates/0.1.2+3-macos'),
            platform: 'macos',
            changes: <String>['Fix'],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'installUpdate throws when the updater has no available item',
      () async {
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive.json'),
            releasePageUrl: Uri.parse('https://example.com/releases'),
            channel: AleraUpdateChannel.rc,
            autoInstallEnabled: true,
            signedRelease: false,
          ),
          desktopUpdater: _FakeDesktopUpdater(),
          platform: 'macos',
        );

        await expectLater(
          service.installUpdate(
            AleraUpdateInfo(
              version: '0.1.4-rc.0',
              shortVersion: 4,
              date: '2026-05-25',
              mandatory: false,
              url: Uri.parse('https://example.com/updates/0.1.4+4-macos'),
              platform: 'macos',
              changes: <String>['Preview'],
            ),
          ),
          throwsStateError,
        );
      },
    );

    test('dispose closes owned clients without throwing', () {
      final service = DesktopAleraUpdateService(platform: 'macos');

      expect(service.dispose, returnsNormally);
      service.dispose();
    });

    test(
      'opens the release page and restarts through injected delegates',
      () async {
        final launched = <Uri>[];
        final updater = _FakeDesktopUpdater();
        final service = DesktopAleraUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: Uri.parse('https://example.com/archive.json'),
            releasePageUrl: Uri.parse(
              'https://github.com/leynier/alera/releases/tag/v0.9.0',
            ),
            channel: AleraUpdateChannel.stable,
            autoInstallEnabled: false,
            signedRelease: false,
          ),
          desktopUpdater: updater,
          launchUrl: (uri) async {
            launched.add(uri);
            return true;
          },
          platform: 'windows',
        );

        await service.openDownloadPage(null);
        await service.openDownloadPage(
          AleraUpdateInfo(
            version: '0.10.0',
            shortVersion: 23,
            date: '2026-07-10',
            mandatory: false,
            url: Uri.parse(
              'https://updates.alera.build/updates/stable/0.10.0+23-linux/alera.deb',
            ),
            platform: 'linux',
            changes: const <String>['Release 0.10.0.'],
          ),
        );
        await service.restartApp();

        expect(launched, <Uri>[
          Uri.parse('https://github.com/leynier/alera/releases/tag/v0.9.0'),
          Uri.parse('https://github.com/leynier/alera/releases/tag/v0.10.0'),
        ]);
        expect(updater.restartCalls, 1);
      },
    );

    test('openDownloadPage uses the default url_launcher delegate', () async {
      final previousPlatform = UrlLauncherPlatform.instance;
      final fakePlatform = _FakeUrlLauncherPlatform();
      UrlLauncherPlatform.instance = fakePlatform;
      addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);
      final service = DesktopAleraUpdateService(
        config: AleraUpdateConfig(
          archiveUrl: Uri.parse('https://example.com/archive.json'),
          releasePageUrl: Uri.parse('https://example.com/releases'),
          channel: AleraUpdateChannel.stable,
          autoInstallEnabled: false,
          signedRelease: false,
        ),
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

PackageInfo _packageInfo({required String buildNumber}) {
  return PackageInfo(
    appName: 'Alera',
    packageName: 'dev.alera',
    version: '0.1.0',
    buildNumber: buildNumber,
  );
}

Future<({String manifest, String publicKey})> _signedArchiveV2Json({
  String channel = 'stable',
  String version = '1.0.0',
  String installerKind = 'deb',
  String artifactUrl = 'https://example.com/alera.deb',
}) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(List.filled(32, 2));
  final keyData = await keyPair.extract();
  final publicKeyData = await keyPair.extractPublicKey();
  final privateKey = base64Encode(keyData.bytes);
  final publicKey = base64Encode(publicKeyData.bytes);
  final decoded = _archiveV2Json(
    channel: channel,
    version: version,
    installerKind: installerKind,
    artifactUrl: artifactUrl,
  );
  final signed = await signAleraManifest(
    manifest: decoded,
    privateKeyBase64: privateKey,
    publicKeyBase64: publicKey,
    publicKeyId: 'test-key',
  );
  return (manifest: jsonEncode(signed), publicKey: publicKey);
}

ItemModel _item({
  required String version,
  required int shortVersion,
  required String url,
  required String platform,
  List<FileHashModel?>? changedFiles,
}) {
  return ItemModel(
    version: version,
    shortVersion: shortVersion,
    changes: <ChangeModel>[ChangeModel(message: 'Preview')],
    date: '2026-05-25',
    mandatory: false,
    url: url,
    platform: platform,
    changedFiles: changedFiles,
  );
}

class _FakeDesktopUpdater extends DesktopUpdater {
  final List<String> checkedArchiveUrls = <String>[];
  final List<String> updatedFolders = <String>[];
  final List<List<FileHashModel?>> updatedChangedFiles =
      <List<FileHashModel?>>[];

  ItemModel? versionCheckResult;
  Stream<UpdateProgress> updateStream = const Stream<UpdateProgress>.empty();
  int restartCalls = 0;

  @override
  Future<ItemModel?> versionCheck({required String appArchiveUrl}) async {
    checkedArchiveUrls.add(appArchiveUrl);
    return versionCheckResult;
  }

  @override
  Future<Stream<UpdateProgress>> updateApp({
    required String remoteUpdateFolder,
    required List<FileHashModel?> changedFiles,
  }) async {
    updatedFolders.add(remoteUpdateFolder);
    updatedChangedFiles.add(changedFiles);
    return updateStream;
  }

  @override
  Future<void> restartApp() async {
    restartCalls += 1;
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

const String _archiveJson = '''
{
  "appName": "Alera",
  "description": "Alera desktop agentic development environment.",
  "items": [
    {
      "version": "0.1.2",
      "shortVersion": 3,
      "changes": [{"type": "fix", "message": "Fix two."}],
      "date": "2026-05-24",
      "mandatory": false,
      "url": "https://example.com/updates/0.1.2+3-macos",
      "platform": "macos"
    },
    {
      "version": "0.1.1",
      "shortVersion": 2,
      "changes": [{"type": "fix", "message": "Linux fix."}],
      "date": "2026-05-24",
      "mandatory": false,
      "url": "https://example.com/updates/0.1.1+2-linux",
      "platform": "linux"
    }
  ]
}
''';

Map<String, Object?> _archiveV2Json({
  required String channel,
  required String version,
  required String installerKind,
  required String artifactUrl,
}) {
  return <String, Object?>{
    'schemaVersion': 2,
    'appName': 'Alera',
    'description': 'Alera desktop agentic development environment.',
    'channel': channel,
    'version': version,
    'buildNumber': 10,
    'publishedAt': '2026-06-06T00:00:00Z',
    'items': <Object?>[
      <String, Object?>{
        'version': version,
        'shortVersion': 10,
        'changes': <Object?>[
          <String, Object?>{'type': 'fix', 'message': 'Fix release.'},
        ],
        'date': '2026-06-06',
        'mandatory': false,
        'platform': 'linux',
        'installerKind': installerKind,
        'url': artifactUrl,
        'sha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'size': 42,
      },
    ],
  };
}
