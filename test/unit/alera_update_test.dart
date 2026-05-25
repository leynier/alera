import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraUpdateConfig', () {
    test('round-trips through json', () {
      final restored = AleraUpdateConfig.fromJson(
        Map<String, Object?>.from(_config.toMap()),
      );

      expect(restored, _config);
      expect(restored.canAutoInstall, isFalse);
    });
  });

  group('AleraUpdateState', () {
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
