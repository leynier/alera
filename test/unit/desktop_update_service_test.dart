import 'dart:io';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/infra/desktop_update_service.dart';
import 'package:alera/src/features/updater/infra/desktop_updater_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  group('DesktopAleraUpdateService', () {
    test('returns an informational message on unsupported platforms', () async {
      final backend = _FakeDesktopUpdaterBackend();
      final service = DesktopAleraUpdateService(
        platform: 'android',
        backend: backend,
      );

      final result = await service.checkForUpdates();

      expect(result.latest, isNull);
      expect(result.message, 'Desktop updates are not available on android.');
      expect(backend.checkCount, 0);
    });

    test(
      'uses the schema 3 backend and enables a signed macOS update',
      () async {
        final backend = _FakeDesktopUpdaterBackend(candidate: _candidate());
        final service = DesktopAleraUpdateService(
          config: _config(
            autoInstallEnabled: true,
            signedRelease: true,
            manifestPublicKey: 'public-key',
            manifestPublicKeyId: 'test-key',
          ),
          loadPackageInfo: () async => _packageInfo('1'),
          platform: 'macos',
          backend: backend,
        );

        final result = await service.checkForUpdates();

        expect(result.latest?.installerKind, 'zip');
        expect(result.autoInstallAllowed, isTrue);
        expect(result.message, 'Update 1.2.3 is ready to install.');
        expect(backend.lastCheck?.archiveUrl, _config().archiveUrl);
        expect(backend.lastCheck?.channel, 'stable');
        expect(backend.lastCheck?.currentVersion, '1.0.0');
        expect(backend.lastCheck?.currentBuildNumber, '1');
        expect(backend.lastCheck?.platform, 'macos');
        expect(backend.lastCheck?.requireSignature, isTrue);
        expect(backend.lastCheck?.publicKeyId, 'test-key');
        expect(backend.lastCheck?.publicKeyBase64, 'public-key');
      },
    );

    test('requires signature configuration for signed builds', () async {
      final service = DesktopAleraUpdateService(
        config: _config(signedRelease: true),
        platform: 'macos',
        backend: _FakeDesktopUpdaterBackend(),
      );

      await expectLater(
        service.checkForUpdates(),
        throwsA(isA<FormatException>()),
      );
    });

    test('handles a missing index and a current build', () async {
      final missing = DesktopAleraUpdateService(
        loadPackageInfo: () async => _packageInfo('1'),
        platform: 'macos',
        backend: _FakeDesktopUpdaterBackend(
          checkError: const DesktopUpdateIndexNotFound(),
        ),
      );
      final current = DesktopAleraUpdateService(
        loadPackageInfo: () async => _packageInfo('1'),
        platform: 'macos',
        backend: _FakeDesktopUpdaterBackend(),
      );

      expect(
        (await missing.checkForUpdates()).message,
        'No update index is published yet.',
      );
      expect((await current.checkForUpdates()).message, 'Alera is up to date.');
    });

    test('propagates update metadata failures', () async {
      final service = DesktopAleraUpdateService(
        loadPackageInfo: () async => _packageInfo('1'),
        platform: 'macos',
        backend: _FakeDesktopUpdaterBackend(
          checkError: const HttpException('boom'),
        ),
      );

      await expectLater(
        service.checkForUpdates(),
        throwsA(isA<HttpException>()),
      );
    });

    for (final installerKind in <String>['deb', 'rpm']) {
      test(
        'maps Linux zip metadata to the local $installerKind package',
        () async {
          final backend = _FakeDesktopUpdaterBackend(
            candidate: _candidate(platform: 'linux'),
          );
          final service = DesktopAleraUpdateService(
            config: _config(autoInstallEnabled: true),
            loadPackageInfo: () async => _packageInfo('1'),
            loadLinuxInstallerKind: () async => installerKind,
            platform: 'linux',
            backend: backend,
          );

          final result = await service.checkForUpdates();

          expect(result.latest?.installerKind, installerKind);
          expect(result.autoInstallAllowed, isFalse);
          expect(
            result.message,
            'Update 1.2.3 is available through the Linux package repository.',
          );
          await expectLater(
            service.installUpdate(result.latest!),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('apt, dnf'),
              ),
            ),
          );
          expect(backend.stagedCandidate, isNull);
        },
      );
    }

    test('reports unsupported Linux distributions as manual', () async {
      final service = DesktopAleraUpdateService(
        config: _config(
          channel: AleraUpdateChannel.rc,
          autoInstallEnabled: true,
        ),
        loadPackageInfo: () async => _packageInfo('1'),
        loadLinuxInstallerKind: () async => null,
        platform: 'linux',
        backend: _FakeDesktopUpdaterBackend(
          candidate: _candidate(platform: 'linux', version: '1.2.3-rc.0'),
        ),
      );

      final result = await service.checkForUpdates();

      expect(result.latest?.installerKind, 'zip');
      expect(result.autoInstallAllowed, isFalse);
      expect(result.message, contains('requires a supported Linux package'));
    });

    test('keeps package-managed installations on their manager path', () async {
      final launched = <Uri>[];
      final service = DesktopAleraUpdateService(
        config: _config(autoInstallEnabled: true),
        loadPackageInfo: () async => _packageInfo('1'),
        launchUrl: (uri) async {
          launched.add(uri);
          return true;
        },
        platform: 'macos',
        packageInstall: const PackageManagerInstall(
          method: PackageInstallMethod.homebrewCask,
          managerExecutable: '/opt/homebrew/bin/brew',
          relaunchExecutable: '/usr/bin/open',
        ),
        backend: _FakeDesktopUpdaterBackend(candidate: _candidate()),
      );

      final result = await service.checkForUpdates();
      await service.openDownloadPage(result.latest);

      expect(result.autoInstallAllowed, isFalse);
      expect(result.message, 'Update 1.2.3 is available through Homebrew.');
      expect(launched.single, AleraUpdateConfig.installGuideUrl);
      await expectLater(
        service.installUpdate(result.latest!),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Homebrew'),
          ),
        ),
      );
    });

    test(
      'stages, reports progress, and installs through desktop_updater',
      () async {
        final backend = _FakeDesktopUpdaterBackend(candidate: _candidate());
        final service = DesktopAleraUpdateService(
          config: _config(autoInstallEnabled: true),
          loadPackageInfo: () async => _packageInfo('1'),
          platform: 'windows',
          backend: backend,
        );
        final result = await service.checkForUpdates();
        final progress = <double>[];

        await service.installUpdate(result.latest!, onProgress: progress.add);
        await service.restartApp();

        expect(backend.stagedCandidate, same(backend.candidate));
        expect(progress, <double>[0.5, 1]);
        expect(backend.installedStagingPath, '/tmp/alera-stage');
        expect(backend.allowUnsignedMacOSUpdates, isTrue);
      },
    );

    test('rejects disabled and stale automatic installs', () async {
      final disabled = DesktopAleraUpdateService(
        config: _config(),
        platform: 'macos',
        backend: _FakeDesktopUpdaterBackend(candidate: _candidate()),
      );
      final enabled = DesktopAleraUpdateService(
        config: _config(autoInstallEnabled: true),
        loadPackageInfo: () async => _packageInfo('1'),
        platform: 'macos',
        backend: _FakeDesktopUpdaterBackend(candidate: _candidate()),
      );

      await expectLater(disabled.installUpdate(_update()), throwsStateError);
      await enabled.checkForUpdates();
      await expectLater(
        enabled.installUpdate(_update(version: '9.0.0')),
        throwsStateError,
      );
      await expectLater(enabled.restartApp(), throwsStateError);
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
        backend: _FakeDesktopUpdaterBackend(),
      );
      final refused = DesktopAleraUpdateService(
        config: _config(),
        launchUrl: (_) async => false,
        platform: 'windows',
        backend: _FakeDesktopUpdaterBackend(),
      );

      await service.openDownloadPage(_update(version: '1.2.3'));

      expect(
        launched.single,
        Uri.parse('https://github.com/leynier/alera/releases/tag/v1.2.3'),
      );
      await expectLater(refused.openDownloadPage(null), throwsStateError);
    });

    test('uses the default launcher and disposes its backend', () async {
      final previousPlatform = UrlLauncherPlatform.instance;
      final fakePlatform = _FakeUrlLauncherPlatform();
      final backend = _FakeDesktopUpdaterBackend();
      UrlLauncherPlatform.instance = fakePlatform;
      addTearDown(() => UrlLauncherPlatform.instance = previousPlatform);
      final service = DesktopAleraUpdateService(
        config: _config(),
        platform: 'macos',
        backend: backend,
      );

      await service.openDownloadPage(null);
      service.dispose();

      expect(fakePlatform.launchedUrls, <String>[
        'https://example.com/releases',
      ]);
      expect(backend.disposed, isTrue);
    });
  });
}

class _FakeDesktopUpdaterBackend implements AleraDesktopUpdaterBackend {
  _FakeDesktopUpdaterBackend({this.candidate, this.checkError});

  final DesktopUpdaterReleaseCandidate? candidate;
  final Object? checkError;
  int checkCount = 0;
  _BackendCheck? lastCheck;
  DesktopUpdaterReleaseCandidate? stagedCandidate;
  String? installedStagingPath;
  bool? allowUnsignedMacOSUpdates;
  bool disposed = false;

  @override
  Future<DesktopUpdaterReleaseCandidate?> checkForUpdate({
    required Uri archiveUrl,
    required String channel,
    required String currentVersion,
    required String currentBuildNumber,
    required String platform,
    required bool requireSignature,
    required String publicKeyId,
    required String publicKeyBase64,
  }) async {
    checkCount += 1;
    lastCheck = (
      archiveUrl: archiveUrl,
      channel: channel,
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
      platform: platform,
      requireSignature: requireSignature,
      publicKeyId: publicKeyId,
      publicKeyBase64: publicKeyBase64,
    );
    final error = checkError;
    if (error != null) {
      throw error;
    }
    return candidate;
  }

  @override
  Future<String> downloadAndStage(
    DesktopUpdaterReleaseCandidate candidate, {
    void Function(double progress)? onProgress,
  }) async {
    stagedCandidate = candidate;
    onProgress?.call(0.5);
    onProgress?.call(1);
    return '/tmp/alera-stage';
  }

  @override
  Future<void> install({
    required String stagingPath,
    required bool allowUnsignedMacOSUpdates,
  }) async {
    installedStagingPath = stagingPath;
    this.allowUnsignedMacOSUpdates = allowUnsignedMacOSUpdates;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

typedef _BackendCheck = ({
  Uri archiveUrl,
  String channel,
  String currentVersion,
  String currentBuildNumber,
  String platform,
  bool requireSignature,
  String publicKeyId,
  String publicKeyBase64,
});

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
  String manifestPublicKeyId = 'alera-release-v1',
}) {
  final stableAutoInstall =
      autoInstallEnabled && channel == AleraUpdateChannel.stable;
  return AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/archive.json'),
    releasePageUrl: releasePageUrl ?? Uri.parse('https://example.com/releases'),
    channel: channel,
    autoInstallEnabled: autoInstallEnabled,
    signedRelease: signedRelease || stableAutoInstall,
    manifestPublicKey: manifestPublicKey.isEmpty && stableAutoInstall
        ? 'public-key'
        : manifestPublicKey,
    manifestPublicKeyId: manifestPublicKeyId,
  );
}

DesktopUpdaterReleaseCandidate _candidate({
  String version = '1.2.3',
  String platform = 'macos',
}) {
  return DesktopUpdaterReleaseCandidate(
    version: version,
    buildNumber: 2,
    generatedAt: DateTime.utc(2026, 7, 27),
    mandatory: false,
    platform: platform,
    artifactKind: 'zip',
    artifactUrl: Uri.parse('https://example.com/alera.zip'),
    artifactSha256: _sha256,
    artifactLength: 42,
  );
}

AleraUpdateInfo _update({
  String version = '1.2.3',
  String platform = 'macos',
  String installerKind = 'zip',
}) {
  return AleraUpdateInfo(
    version: version,
    shortVersion: 2,
    date: '2026-07-27',
    mandatory: false,
    url: Uri.parse('https://example.com/alera.zip'),
    platform: platform,
    changes: const <String>[],
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

const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
