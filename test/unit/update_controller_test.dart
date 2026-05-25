import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraUpdateController', () {
    test('marks state as not available when no update exists', () async {
      final service = _FakeUpdateService(
        result: const AleraUpdateCheckResult(message: 'No update.'),
      );
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();

      expect(
        container.read(aleraUpdateControllerProvider).status,
        AleraUpdateStatus.notAvailable,
      );
      expect(
        container.read(aleraUpdateControllerProvider).message,
        'No update.',
      );
    });

    test('marks unsigned stable updates as manual downloads', () async {
      final service = _FakeUpdateService(
        config: AleraUpdateConfig(
          archiveUrl: _archiveUrl,
          releasePageUrl: _releasePageUrl,
          channel: AleraUpdateChannel.stable,
          autoInstallEnabled: false,
          signedRelease: false,
        ),
        result: AleraUpdateCheckResult(latest: _update),
      );
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();

      expect(
        container.read(aleraUpdateControllerProvider).status,
        AleraUpdateStatus.manualDownloadRequired,
      );
      expect(container.read(aleraUpdateControllerProvider).latest, _update);
    });

    test('marks auto-installable updates as available', () async {
      final service = _FakeUpdateService(
        config: AleraUpdateConfig(
          archiveUrl: _archiveUrl,
          releasePageUrl: _releasePageUrl,
          channel: AleraUpdateChannel.rc,
          autoInstallEnabled: true,
          signedRelease: false,
        ),
        result: AleraUpdateCheckResult(
          latest: _update,
          autoInstallAllowed: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();

      expect(
        container.read(aleraUpdateControllerProvider).status,
        AleraUpdateStatus.available,
      );
    });

    test('opens the manual download page', () async {
      final service = _FakeUpdateService(
        result: AleraUpdateCheckResult(latest: _update),
      );
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();
      await controller.openDownloadPage();

      expect(service.openedUpdate, _update);
    });

    test(
      'downloads an auto-installable update and reaches downloaded state',
      () async {
        final service = _FakeUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: _archiveUrl,
            releasePageUrl: _releasePageUrl,
            channel: AleraUpdateChannel.rc,
            autoInstallEnabled: true,
            signedRelease: false,
          ),
          result: AleraUpdateCheckResult(
            latest: _update,
            autoInstallAllowed: true,
          ),
        );
        final container = ProviderContainer(
          overrides: [updateServiceProvider.overrideWithValue(service)],
        );
        addTearDown(container.dispose);
        final controller = container.read(
          aleraUpdateControllerProvider.notifier,
        );

        await controller.checkForUpdates();
        await controller.installLatest();

        expect(
          container.read(aleraUpdateControllerProvider).status,
          AleraUpdateStatus.downloaded,
        );
        expect(container.read(aleraUpdateControllerProvider).progress, 1);
        expect(service.installedUpdate, _update);
      },
    );
  });
}

class _FakeUpdateService implements AleraUpdateService {
  _FakeUpdateService({
    this.result = const AleraUpdateCheckResult(),
    AleraUpdateConfig? config,
  }) : config =
           config ??
           AleraUpdateConfig(
             archiveUrl: _archiveUrl,
             releasePageUrl: _releasePageUrl,
             channel: AleraUpdateChannel.stable,
             autoInstallEnabled: false,
             signedRelease: false,
           );

  @override
  final AleraUpdateConfig config;

  final AleraUpdateCheckResult result;
  AleraUpdateInfo? openedUpdate;
  AleraUpdateInfo? installedUpdate;

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async => result;

  @override
  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    installedUpdate = update;
    onProgress?.call(0.4);
    onProgress?.call(1);
  }

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {
    openedUpdate = update;
  }

  @override
  Future<void> restartApp() async {}

  @override
  void dispose() {}
}

final Uri _archiveUrl = Uri.parse('https://example.com/app-archive.json');
final Uri _releasePageUrl = Uri.parse('https://github.com/leynier/alera');
final AleraUpdateInfo _update = AleraUpdateInfo(
  version: '0.1.1',
  shortVersion: 2,
  date: '2026-05-24',
  mandatory: false,
  url: Uri.parse('https://example.com/updates/0.1.1+2-macos'),
  platform: 'macos',
  changes: <String>['Fix one.'],
);
