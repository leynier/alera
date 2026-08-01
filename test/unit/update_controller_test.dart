import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraUpdateController', () {
    test('marks state as not available when no update exists', () async {
      final service = _FakeUpdateService(
        result: const AleraUpdateCheckResult(message: 'No update.'),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
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
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
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
          currentVersion: '0.1.0',
          currentBuildNumber: '1',
        ),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();

      expect(
        container.read(aleraUpdateControllerProvider).status,
        AleraUpdateStatus.available,
      );
      expect(
        container.read(aleraUpdateControllerProvider).currentVersion,
        '0.1.0',
      );
      expect(
        container.read(aleraUpdateControllerProvider).currentBuildNumber,
        '1',
      );
    });

    test('surfaces check-for-updates failures', () async {
      final service = _FakeUpdateService(
        checkError: StateError('network down'),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();

      expect(
        container.read(aleraUpdateControllerProvider).status,
        AleraUpdateStatus.error,
      );
      expect(
        container.read(aleraUpdateControllerProvider).message,
        contains('network down'),
      );
    });

    test('opens the manual download page', () async {
      final service = _FakeUpdateService(
        result: AleraUpdateCheckResult(latest: _update),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();
      await controller.openDownloadPage();

      expect(service.openedUpdate, _update);
    });

    test(
      'installLatest opens the download page when auto-install is disabled',
      () async {
        final service = _FakeUpdateService(
          result: AleraUpdateCheckResult(latest: _update),
        );
        final container = ProviderContainer(
          overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
        );
        addTearDown(container.dispose);
        final controller = container.read(
          aleraUpdateControllerProvider.notifier,
        );

        await controller.checkForUpdates();
        await controller.installLatest();

        expect(service.openedUpdate, _update);
        expect(service.installedUpdate, isNull);
      },
    );

    test(
      'installs an auto-installable update and completes the handoff',
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
          overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
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
        expect(service.restartCalls, 1);
      },
    );

    test('installLatest surfaces download failures', () async {
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
        installError: StateError('disk full'),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();
      await controller.installLatest();

      expect(
        container.read(aleraUpdateControllerProvider).status,
        AleraUpdateStatus.error,
      );
      expect(
        container.read(aleraUpdateControllerProvider).message,
        contains('disk full'),
      );
    });

    test('installLatest keeps Alera usable when handoff fails', () async {
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
        restartError: StateError('helper unavailable'),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();
      await controller.installLatest();

      final state = container.read(aleraUpdateControllerProvider);
      expect(state.status, AleraUpdateStatus.error);
      expect(state.message, contains('helper unavailable'));
      expect(state.message, contains('Alera is still running'));
    });

    // A Homebrew or Scoop installation must never be replaced behind the
    // manager's back, so the same button hands the upgrade to the manager.
    test(
      'installLatest hands a managed install to its package manager',
      () async {
        final service = _FakeUpdateService(
          config: AleraUpdateConfig(
            archiveUrl: _archiveUrl,
            releasePageUrl: _releasePageUrl,
            channel: AleraUpdateChannel.stable,
            autoInstallEnabled: true,
            signedRelease: false,
          ),
          result: AleraUpdateCheckResult(latest: _update),
          packageInstall: const PackageManagerInstall(
            method: PackageInstallMethod.homebrewCask,
            managerExecutable: '/opt/homebrew/bin/brew',
            relaunchExecutable: '/usr/bin/open',
          ),
        );
        final container = ProviderContainer(
          overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
        );
        addTearDown(container.dispose);
        final controller = container.read(
          aleraUpdateControllerProvider.notifier,
        );

        await controller.checkForUpdates();
        await controller.installLatest();

        expect(service.packageUpgradeCalls, 1);
        expect(service.installedUpdate, isNull);
        final state = container.read(aleraUpdateControllerProvider);
        expect(state.status, AleraUpdateStatus.applying);
        expect(state.message, contains('Homebrew'));
      },
    );

    test('keeps Alera usable when the package upgrade cannot start', () async {
      final service = _FakeUpdateService(
        result: AleraUpdateCheckResult(latest: _update),
        packageInstall: const PackageManagerInstall(
          method: PackageInstallMethod.scoop,
          managerExecutable: r'C:\scoop\shims\scoop.cmd',
          relaunchExecutable: r'C:\scoop\apps\alera\current\Alera.exe',
        ),
        packageUpgradeError: StateError('scoop missing'),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();
      await controller.installLatest();

      final state = container.read(aleraUpdateControllerProvider);
      expect(state.status, AleraUpdateStatus.error);
      expect(state.message, contains('scoop missing'));
      expect(state.message, contains('Alera is still running'));
    });

    // Chocolatey needs elevation, so Alera only ever shows its command.
    test('never runs the upgrade for a Chocolatey install', () async {
      final service = _FakeUpdateService(
        result: AleraUpdateCheckResult(latest: _update),
        packageInstall: const PackageManagerInstall(
          method: PackageInstallMethod.chocolatey,
        ),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();
      await controller.installLatest();

      expect(service.packageUpgradeCalls, 0);
      expect(service.openedUpdate, _update);
    });

    test('restartApp delegates to the update service', () async {
      final service = _FakeUpdateService();
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.restartApp();

      expect(service.restartCalls, 1);
    });

    test('manual command completion exposes the restart state', () async {
      final service = _FakeUpdateService(
        result: AleraUpdateCheckResult(latest: _update),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.checkForUpdates();
      controller.requireRestartAfterManualUpdate();

      final state = container.read(aleraUpdateControllerProvider);
      expect(state.status, AleraUpdateStatus.restartRequired);
      expect(state.message, contains('Restart Alera'));
      expect(state.latest, _update);
    });

    test('restartApp reports a relaunch failure', () async {
      final service = _FakeUpdateService(
        restartError: StateError('relaunch unavailable'),
      );
      final container = ProviderContainer(
        overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(aleraUpdateControllerProvider.notifier);

      await controller.restartApp();

      final state = container.read(aleraUpdateControllerProvider);
      expect(state.status, AleraUpdateStatus.error);
      expect(state.message, contains('relaunch unavailable'));
    });
  });
}

class _FakeUpdateService implements AleraUpdateService {
  _FakeUpdateService({
    this.result = const AleraUpdateCheckResult(),
    AleraUpdateConfig? config,
    this.checkError,
    this.installError,
    this.restartError,
    this.packageInstall = PackageManagerInstall.unmanaged,
    this.packageUpgradeError,
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
  final Object? checkError;
  final Object? installError;
  final Object? restartError;

  @override
  final PackageManagerInstall packageInstall;

  final Object? packageUpgradeError;
  AleraUpdateInfo? openedUpdate;
  AleraUpdateInfo? installedUpdate;
  int restartCalls = 0;
  int packageUpgradeCalls = 0;

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    if (checkError case final Object error) {
      throw error;
    }
    return result;
  }

  @override
  Future<void> upgradeThroughPackageManager() async {
    packageUpgradeCalls += 1;
    if (packageUpgradeError case final Object error) {
      throw error;
    }
  }

  @override
  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    if (installError case final Object error) {
      throw error;
    }
    installedUpdate = update;
    onProgress?.call(0.4);
    onProgress?.call(1);
  }

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {
    openedUpdate = update;
  }

  @override
  Future<void> restartApp() async {
    if (restartError case final Object error) {
      throw error;
    }
    restartCalls += 1;
  }

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
