import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter_riverpod/legacy.dart';

class AleraUpdateController extends StateNotifier<AleraUpdateState> {
  AleraUpdateController(this._service)
    : super(AleraUpdateState.idle(_service.config));

  final AleraUpdateService _service;

  Future<void> checkForUpdates() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(
      status: AleraUpdateStatus.checking,
      progress: 0,
      message: 'Checking for updates.',
      clearLatest: true,
    );

    try {
      final result = await _service.checkForUpdates();
      if (!mounted) {
        return;
      }
      final latest = result.latest;
      if (latest == null) {
        state = state.copyWith(
          status: AleraUpdateStatus.notAvailable,
          message: result.message ?? 'Alera is up to date.',
          clearLatest: true,
          progress: 0,
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
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        status: AleraUpdateStatus.error,
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
    if (!state.config.canAutoInstall) {
      await openDownloadPage();
      return;
    }

    state = state.copyWith(
      status: AleraUpdateStatus.downloading,
      message: 'Downloading update ${latest.version}.',
      progress: 0,
    );

    try {
      await _service.installUpdate(
        latest,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          state = state.copyWith(progress: progress.clamp(0, 1).toDouble());
        },
      );
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        status: AleraUpdateStatus.downloaded,
        message: 'Update downloaded. Restart Alera to finish installing.',
        progress: 1,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        status: AleraUpdateStatus.error,
        message: 'Update download failed: $error',
      );
    }
  }

  Future<void> openDownloadPage() {
    return _service.openDownloadPage(state.latest);
  }

  Future<void> restartApp() {
    return _service.restartApp();
  }
}
