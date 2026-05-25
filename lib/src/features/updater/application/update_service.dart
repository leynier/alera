import 'package:alera/src/features/updater/domain/alera_update.dart';

class AleraUpdateCheckResult {
  const AleraUpdateCheckResult({
    this.latest,
    this.autoInstallAllowed = false,
    this.message,
  });

  final AleraUpdateInfo? latest;
  final bool autoInstallAllowed;
  final String? message;
}

abstract class AleraUpdateService {
  AleraUpdateConfig get config;

  Future<AleraUpdateCheckResult> checkForUpdates();

  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  });

  Future<void> openDownloadPage(AleraUpdateInfo? update);

  Future<void> restartApp();

  void dispose();
}
