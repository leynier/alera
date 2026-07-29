import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';

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

  /// The package manager that owns this installation, if any.
  PackageManagerInstall get packageInstall;

  Future<AleraUpdateCheckResult> checkForUpdates();

  /// Runs the owning package manager's upgrade and brings Alera back.
  ///
  /// Only valid when [PackageManagerInstall.canRunUpgrade]; the app closes as
  /// part of this call, because the install directory cannot be replaced while
  /// it is in use.
  Future<void> upgradeThroughPackageManager();

  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  });

  Future<void> openDownloadPage(AleraUpdateInfo? update);

  Future<void> restartApp();

  void dispose();
}
