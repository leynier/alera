import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/application/update_providers.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('throttles progress state updates for large downloads', () async {
    final service = _ProgressUpdateService(
      progressValues: [
        for (var index = 0; index <= 1000; index++) index / 1000,
      ],
    );
    final container = ProviderContainer(
      overrides: [aleraUpdateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final published = <double>[];
    final subscription = container.listen<AleraUpdateState>(
      aleraUpdateControllerProvider,
      (_, next) {
        if (next.status == AleraUpdateStatus.downloading) {
          published.add(next.progress);
        }
      },
    );
    addTearDown(subscription.close);
    final controller = container.read(aleraUpdateControllerProvider.notifier);

    await controller.checkForUpdates();
    await controller.installLatest();

    expect(published.length, lessThan(150));
    expect(published.last, 1);
  });
}

class _ProgressUpdateService implements AleraUpdateService {
  _ProgressUpdateService({required this.progressValues});

  static final _config = AleraUpdateConfig(
    archiveUrl: Uri.parse('https://example.com/app-archive.json'),
    releasePageUrl: Uri.parse('https://github.com/leynier/alera'),
    channel: .rc,
    autoInstallEnabled: true,
    signedRelease: false,
  );
  static final _update = AleraUpdateInfo(
    version: '0.1.1',
    shortVersion: 2,
    date: '2026-05-24',
    mandatory: false,
    url: Uri.parse('https://example.com/updates/0.1.1+2-macos'),
    platform: 'macos',
    changes: ['Fix one.'],
  );

  final List<double> progressValues;

  @override
  AleraUpdateConfig get config => _config;

  @override
  PackageManagerInstall get packageInstall => PackageManagerInstall.unmanaged;

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    return AleraUpdateCheckResult(latest: _update, autoInstallAllowed: true);
  }

  @override
  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    for (final progress in progressValues) {
      onProgress?.call(progress);
    }
  }

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {}

  @override
  Future<void> restartApp() async {}

  @override
  Future<void> upgradeThroughPackageManager() async {}

  @override
  void dispose() {}
}
