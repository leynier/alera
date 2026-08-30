import 'package:alera/src/features/updater/application/update_providers.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:logging/logging.dart';

part 'update_controller.g.dart';

final Logger _log = Logger('UpdateController');

@Riverpod(keepAlive: true)
class AleraUpdateController extends _$AleraUpdateController {
  bool _disposed = false;

  AleraUpdateService get _service => ref.read(aleraUpdateServiceProvider);

  @override
  AleraUpdateState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
    });
    final service = ref.read(aleraUpdateServiceProvider);
    return AleraUpdateState.idle(service.config);
  }

  Future<void> checkForUpdates() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(
      status: .checking,
      progress: 0,
      message: 'Checking for updates.',
      latest: null,
    );

    try {
      final result = await _service.checkForUpdates();
      if (_disposed) {
        return;
      }
      final latest = result.latest;
      if (latest == null) {
        state = state.copyWith(
          status: .notAvailable,
          message: result.message ?? 'Alera is up to date.',
          latest: null,
          progress: 0,
          currentVersion: result.currentVersion,
          currentBuildNumber: result.currentBuildNumber,
        );
        return;
      }

      state = state.copyWith(
        status: result.autoInstallAllowed
            ? AleraUpdateStatus.available
            : AleraUpdateStatus.manualDownloadRequired,
        latest: latest,
        message:
            result.message ??
            (result.autoInstallAllowed
                ? 'Update ${latest.version} is ready to install.'
                : 'Update ${latest.version} is available for manual download.'),
        progress: 0,
        currentVersion: result.currentVersion,
        currentBuildNumber: result.currentBuildNumber,
      );
    } catch (error, stackTrace) {
      _log.warning('update check failed', error, stackTrace);
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        status: .error,
        message: 'Update check failed: $error',
        progress: 0,
      );
    }
  }

  Future<void> installLatest() async {
    final latest = state.latest;
    if (latest == null || state.isBusy) {
      return;
    }
    if (_service.packageInstall.canRunUpgrade) {
      await upgradeThroughPackageManager();
      return;
    }
    if (!state.config.canAutoInstall) {
      await openDownloadPage();
      return;
    }

    state = state.copyWith(
      status: .downloading,
      message: 'Downloading update ${latest.version}.',
      progress: 0,
    );

    try {
      await _service.installUpdate(
        latest,
        onProgress: (progress) {
          if (_disposed) {
            return;
          }
          state = state.copyWith(progress: progress.clamp(0, 1).toDouble());
        },
      );
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        status: .applying,
        message: 'Installing update ${latest.version}. Alera will restart.',
        progress: 1,
      );
      await _service.restartApp();
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        status: .downloaded,
        message: 'Update handoff complete. Alera will restart shortly.',
        progress: 1,
      );
    } catch (error, stackTrace) {
      // The banner message is gone as soon as it is dismissed, and a failed
      // install is exactly the kind of thing reported after the fact.
      _log.severe('update installation failed', error, stackTrace);
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        status: .error,
        message:
            'Update installation failed: $error '
            'Alera is still running. Try again.',
      );
    }
  }

  /// Hands the upgrade to the package manager that owns this installation.
  ///
  /// Alera closes as part of this call and the helper reopens it, so the
  /// success path never reaches the state assignment below: only a failure to
  /// even start the helper does.
  Future<void> upgradeThroughPackageManager() async {
    if (state.isBusy) {
      return;
    }
    final manager = packageManagerLabel(_service.packageInstall.method);
    state = state.copyWith(
      status: .applying,
      message: 'Upgrading through $manager. Alera will close and reopen.',
      progress: 0,
    );
    try {
      await _service.upgradeThroughPackageManager();
    } catch (error) {
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        status: .error,
        message:
            'The $manager upgrade could not be started: $error '
            'Alera is still running. Try the command below instead.',
        progress: 0,
      );
    }
  }

  Future<void> openDownloadPage() {
    return _service.openDownloadPage(state.latest);
  }

  void requireRestartAfterManualUpdate() {
    if (state.latest == null || state.isBusy) {
      return;
    }
    state = state.copyWith(
      status: .restartRequired,
      message: 'Restart Alera to load any update installed by the command.',
      progress: 0,
    );
  }

  Future<void> restartApp() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(
      status: .applying,
      message: 'Restarting Alera.',
      progress: 0,
    );
    try {
      await _service.restartApp();
    } catch (error, stackTrace) {
      _log.warning('app restart failed', error, stackTrace);
      if (_disposed) {
        return;
      }
      state = state.copyWith(
        status: .error,
        message: 'Alera could not restart: $error',
        progress: 0,
      );
    }
  }
}
