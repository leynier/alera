import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraUpdateChannel', () {
    test('parses release-candidate aliases and stable fallbacks', () {
      expect(AleraUpdateChannel.parse('rc'), AleraUpdateChannel.rc);
      expect(
        AleraUpdateChannel.parse('release-candidate'),
        AleraUpdateChannel.rc,
      );
      expect(AleraUpdateChannel.parse('stable'), AleraUpdateChannel.stable);
    });
  });

  group('AleraUpdateConfig', () {
    test('exposes the canonical default URLs and environment defaults', () {
      expect(
        AleraUpdateConfig.defaultArchiveUrl,
        Uri.parse('https://updates.alera.build/app-archive.json'),
      );
      expect(
        AleraUpdateConfig.defaultReleasePageUrl,
        Uri.parse('https://github.com/leynier/alera/releases'),
      );

      final config = AleraUpdateConfig.fromEnvironment();
      expect(config.archiveUrl, AleraUpdateConfig.defaultArchiveUrl);
      expect(config.releasePageUrl, AleraUpdateConfig.defaultReleasePageUrl);
    });

    test('round-trips through json', () {
      final restored = AleraUpdateConfig.fromJson(
        Map<String, Object?>.from(_config.toMap()),
      );

      expect(restored, _config);
      expect(restored.canAutoInstall, isFalse);
    });

    test('resolves environment uris with defaults when values are null', () {
      expect(
        resolveUpdateConfigUriForTesting(
          null,
          AleraUpdateConfig.defaultArchiveUrl,
        ),
        AleraUpdateConfig.defaultArchiveUrl,
      );
      expect(
        resolveUpdateConfigUriForTesting(
          Uri.parse('https://example.com/archive.json'),
          AleraUpdateConfig.defaultArchiveUrl,
        ),
        Uri.parse('https://example.com/archive.json'),
      );
      expect(
        resolveUpdateConfigUriForTesting(
          null,
          AleraUpdateConfig.defaultReleasePageUrl,
        ),
        AleraUpdateConfig.defaultReleasePageUrl,
      );
    });

    test(
      'downloadPageUrlFor maps a detected update to its release tag page',
      () {
        final listRoot = AleraUpdateConfig(
          archiveUrl: Uri.parse('https://example.com/app-archive.json'),
          releasePageUrl: Uri.parse(
            'https://github.com/leynier/alera/releases',
          ),
          channel: AleraUpdateChannel.stable,
          autoInstallEnabled: false,
          signedRelease: false,
        );
        final bakedCurrent = listRoot.copyWith(
          releasePageUrl: Uri.parse(
            'https://github.com/leynier/alera/releases/tag/v0.9.0',
          ),
        );

        expect(listRoot.downloadPageUrlFor(null), listRoot.releasePageUrl);
        expect(
          listRoot.downloadPageUrlFor(_update),
          Uri.parse('https://github.com/leynier/alera/releases/tag/v0.1.2'),
        );
        expect(
          bakedCurrent.downloadPageUrlFor(_update),
          Uri.parse('https://github.com/leynier/alera/releases/tag/v0.1.2'),
        );
        expect(
          bakedCurrent.downloadPageUrlFor(
            _update.copyWith(version: 'v0.10.0-rc.1'),
          ),
          Uri.parse(
            'https://github.com/leynier/alera/releases/tag/v0.10.0-rc.1',
          ),
        );
      },
    );

    test('resolveAleraReleaseTagPageUrl falls back without a releases segment', () {
      expect(
        resolveAleraReleaseTagPageUrl(
          releasePageUrl: Uri.parse('https://example.com/downloads'),
          version: '1.2.3',
        ),
        Uri.parse('https://example.com/downloads/tag/v1.2.3'),
      );
      expect(
        resolveAleraReleaseTagPageUrl(
          releasePageUrl: Uri.parse(
            'https://github.com/leynier/alera/releases/tag/v0.9.0',
          ),
          version: '  ',
        ),
        Uri.parse('https://github.com/leynier/alera/releases/tag/v0.9.0'),
      );
    });
  });

  group('AleraUpdateState', () {
    test('exposes all status values in order', () {
      expect(AleraUpdateStatus.values, <AleraUpdateStatus>[
        AleraUpdateStatus.idle,
        AleraUpdateStatus.checking,
        AleraUpdateStatus.notAvailable,
        AleraUpdateStatus.manualDownloadRequired,
        AleraUpdateStatus.available,
        AleraUpdateStatus.downloading,
        AleraUpdateStatus.downloaded,
        AleraUpdateStatus.error,
      ]);
    });

    test('update info round-trips through json and detects prereleases', () {
      final restored = AleraUpdateInfo.fromJson(
        Map<String, Object?>.from(_update.toMap()),
      );

      expect(restored, _update);
      expect(restored.platform, 'macos');
      expect(restored.isPrerelease, isFalse);
      expect(
        AleraUpdateInfo.fromJson(
          Map<String, Object?>.from(
            _update.copyWith(version: '0.1.2-rc.1').toMap(),
          ),
        ).isPrerelease,
        isTrue,
      );
    });

    test('copyWith updates and clears nullable fields', () {
      final state = AleraUpdateState(
        status: AleraUpdateStatus.available,
        config: _config,
        latest: _update,
        message: 'Update is ready.',
        progress: 0.4,
      );

      final updated = state.copyWith(
        status: AleraUpdateStatus.checking,
        latest: null,
        message: null,
        progress: 0,
      );

      expect(updated.status, AleraUpdateStatus.checking);
      expect(updated.config, _config);
      expect(updated.latest, isNull);
      expect(updated.message, isNull);
      expect(updated.progress, 0);
    });

    test('idle state starts non-busy and keeps the provided config', () {
      final state = AleraUpdateState.idle(_config);

      expect(state.status, AleraUpdateStatus.idle);
      expect(state.config, _config);
      expect(state.latest, isNull);
      expect(state.message, isNull);
      expect(state.progress, 0);
      expect(state.isBusy, isFalse);
    });

    test('round-trips through json', () {
      final state = AleraUpdateState(
        status: AleraUpdateStatus.manualDownloadRequired,
        config: _config,
        latest: _update,
        message: 'Download the latest release manually.',
        progress: 0,
      );

      final restored = AleraUpdateState.fromJson(
        Map<String, Object?>.from(state.toMap()),
      );

      expect(restored, state);
      expect(restored.latest, _update);
    });

    test('isBusy is true while checking or downloading', () {
      expect(
        AleraUpdateState(
          status: AleraUpdateStatus.checking,
          config: _config,
        ).isBusy,
        isTrue,
      );
      expect(
        AleraUpdateState(
          status: AleraUpdateStatus.downloading,
          config: _config,
        ).isBusy,
        isTrue,
      );
    });
  });
}

final AleraUpdateConfig _config = AleraUpdateConfig(
  archiveUrl: Uri.parse('https://example.com/app-archive.json'),
  releasePageUrl: Uri.parse('https://github.com/leynier/alera/releases'),
  channel: AleraUpdateChannel.stable,
  autoInstallEnabled: true,
  signedRelease: false,
);

final AleraUpdateInfo _update = AleraUpdateInfo(
  version: '0.1.2',
  shortVersion: 3,
  date: '2026-05-24',
  mandatory: false,
  url: Uri.parse('https://example.com/updates/0.1.2+3-macos'),
  platform: 'macos',
  changes: <String>['Fix one.', 'Fix two.'],
);
