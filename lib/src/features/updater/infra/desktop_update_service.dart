import 'dart:io';

import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/infra/desktop_updater_backend.dart';
import 'package:alera/src/features/updater/infra/linux_update_package.dart';
import 'package:alera/src/features/updater/infra/package_manager_update_launcher.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/process/rust_process_runner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef AleraUrlLauncher = Future<bool> Function(Uri uri);
typedef LinuxInstallerKindLoader = Future<String?> Function();

class DesktopAleraUpdateService implements AleraUpdateService {
  DesktopAleraUpdateService({
    AleraUpdateConfig? config,
    PackageInfoLoader? loadPackageInfo,
    AleraUrlLauncher? launchUrl,
    String? platform,
    LinuxInstallerKindLoader? loadLinuxInstallerKind,
    AleraDesktopUpdaterBackend? backend,
    ProcessRunner? processRunner,
    String? resolvedExecutable,
    int? processId,
    AleraAppExit? exitApp,
    PackageManagerInstall? packageInstall,
    PackageManagerUpdateLauncher? packageManagerLauncher,
  }) : config = config ?? AleraUpdateConfig.fromEnvironment(),
       _loadPackageInfo = loadPackageInfo ?? PackageInfo.fromPlatform,
       _launchUrl = launchUrl ?? _launchExternalUrl,
       _platform = platform ?? Platform.operatingSystem,
       _loadLinuxInstallerKind =
           loadLinuxInstallerKind ?? loadDesktopLinuxInstallerKind,
       _backend = backend ?? DesktopUpdaterBackend() {
    _packageInstall =
        packageInstall ??
        packageManagerInstallFromExecutablePath(
          platform: _platform,
          executablePath: resolvedExecutable ?? Platform.resolvedExecutable,
        );
    _packageManagerLauncher =
        packageManagerLauncher ??
        PackageManagerUpdateLauncher(
          processRunner: processRunner ?? const RustProcessRunner(),
          processId: processId,
          exitApp: exitApp,
        );
  }

  static const Set<String> _supportedPlatforms = <String>{
    'linux',
    'macos',
    'windows',
  };
  static const Set<String> _installableArtifactKinds = <String>{
    'zip',
    'dmg',
    'pkgInstaller',
    'innoInstaller',
  };

  @override
  final AleraUpdateConfig config;

  final PackageInfoLoader _loadPackageInfo;
  final AleraUrlLauncher _launchUrl;
  final String _platform;
  final LinuxInstallerKindLoader _loadLinuxInstallerKind;
  final AleraDesktopUpdaterBackend _backend;
  late final PackageManagerInstall _packageInstall;
  late final PackageManagerUpdateLauncher _packageManagerLauncher;
  DesktopUpdaterReleaseCandidate? _activeCandidate;
  AleraUpdateInfo? _activeUpdate;
  String? _stagingPath;

  @override
  PackageManagerInstall get packageInstall => _packageInstall;

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    if (!_supportedPlatforms.contains(_platform)) {
      return AleraUpdateCheckResult(
        message: 'Desktop updates are not available on $_platform.',
      );
    }
    if (config.signedRelease &&
        (config.manifestPublicKey.trim().isEmpty ||
            config.manifestPublicKeyId.trim().isEmpty)) {
      throw const FormatException(
        'Signed desktop updates require a public key and key id.',
      );
    }

    final packageInfo = await _loadPackageInfo();
    late final DesktopUpdaterReleaseCandidate? candidate;
    try {
      candidate = await _backend.checkForUpdate(
        archiveUrl: config.archiveUrl,
        channel: config.channel.name,
        currentVersion: packageInfo.version,
        currentBuildNumber: packageInfo.buildNumber,
        platform: _platform,
        requireSignature: config.signedRelease,
        publicKeyId: config.manifestPublicKeyId,
        publicKeyBase64: config.manifestPublicKey,
      );
    } on DesktopUpdateIndexNotFound {
      _clearSelection();
      return const AleraUpdateCheckResult(
        message: 'No update index is published yet.',
      );
    }
    if (candidate == null) {
      _clearSelection();
      return const AleraUpdateCheckResult(message: 'Alera is up to date.');
    }

    final update = await _toAleraUpdate(candidate);
    _activeCandidate = candidate;
    _activeUpdate = update;
    _stagingPath = null;

    final autoInstallAllowed =
        config.canAutoInstall &&
        _platform != 'linux' &&
        !_packageInstall.isPackageManaged &&
        _installableArtifactKinds.contains(candidate.artifactKind);
    if (autoInstallAllowed) {
      return AleraUpdateCheckResult(
        latest: update,
        autoInstallAllowed: true,
        message: 'Update ${update.version} is ready to install.',
      );
    }

    return AleraUpdateCheckResult(
      latest: update,
      message: _manualUpdateMessage(
        config: config,
        update: update,
        packageInstall: _packageInstall,
      ),
    );
  }

  @override
  Future<void> installUpdate(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    if (!config.canAutoInstall) {
      throw StateError('Automatic update installation is disabled.');
    }
    final manager = packageManagerLabel(_packageInstall.method);
    if (manager != null) {
      throw StateError(
        'Alera does not replace an installation $manager owns. Upgrade '
        'through $manager instead.',
      );
    }
    if (_platform == 'linux') {
      throw StateError(
        'Automatic Linux updates are disabled. Install Alera through apt, '
        'dnf, or the configured package repository.',
      );
    }
    final candidate = _activeCandidate;
    if (candidate == null || !_matchesActiveUpdate(update)) {
      throw StateError('The selected desktop update is no longer active.');
    }
    if (!_installableArtifactKinds.contains(candidate.artifactKind)) {
      throw StateError(
        'Automatic installation does not support '
        '${candidate.platform} ${candidate.artifactKind} artifacts.',
      );
    }

    _stagingPath = await _backend.downloadAndStage(
      candidate,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> upgradeThroughPackageManager() {
    return _packageManagerLauncher.upgradeAndRestart(_packageInstall);
  }

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {
    final destination = _packageInstall.isPackageManaged || _platform == 'linux'
        ? AleraUpdateConfig.installGuideUrl
        : config.downloadPageUrlFor(update);
    final launched = await _launchUrl(destination);
    if (!launched) {
      throw StateError('The release download page could not be opened.');
    }
  }

  @override
  Future<void> restartApp() async {
    final stagingPath = _stagingPath;
    if (stagingPath == null || stagingPath.isEmpty) {
      throw StateError('No verified update is ready to install.');
    }
    await _backend.install(
      stagingPath: stagingPath,
      // Alera's Ed25519 descriptor and artifact hash are the update trust
      // root. Platform signing remains optional for public releases.
      allowUnsignedMacOSUpdates: true,
    );
    _stagingPath = null;
  }

  @override
  void dispose() {
    _clearSelection();
    _backend.dispose();
  }

  Future<AleraUpdateInfo> _toAleraUpdate(
    DesktopUpdaterReleaseCandidate candidate,
  ) async {
    final installerKind = _platform == 'linux'
        ? await _loadLinuxInstallerKind() ?? candidate.artifactKind
        : candidate.artifactKind;
    return AleraUpdateInfo(
      version: candidate.version,
      shortVersion: candidate.buildNumber ?? 0,
      date: candidate.generatedAt.toUtc().toIso8601String().split('T').first,
      mandatory: candidate.mandatory,
      url: candidate.artifactUrl,
      platform: candidate.platform,
      changes: const <String>[],
      installerKind: installerKind,
      sha256: candidate.artifactSha256,
      size: candidate.artifactLength,
    );
  }

  bool _matchesActiveUpdate(AleraUpdateInfo update) {
    final active = _activeUpdate;
    return active != null &&
        active.version == update.version &&
        active.shortVersion == update.shortVersion &&
        active.platform == update.platform;
  }

  void _clearSelection() {
    _activeCandidate = null;
    _activeUpdate = null;
    _stagingPath = null;
  }
}

String _manualUpdateMessage({
  required AleraUpdateConfig config,
  required AleraUpdateInfo update,
  required PackageManagerInstall packageInstall,
}) {
  final manager = packageManagerLabel(packageInstall.method);
  if (manager != null) {
    return 'Update ${update.version} is available through $manager.';
  }
  if (update.platform == 'linux' &&
      config.channel == AleraUpdateChannel.stable &&
      (update.installerKind == 'deb' || update.installerKind == 'rpm')) {
    return 'Update ${update.version} is available through the Linux package repository.';
  }
  if (update.platform == 'linux') {
    return 'Update ${update.version} requires a supported Linux package. '
        'See ${AleraUpdateConfig.installGuideUrl}.';
  }
  return 'Update ${update.version} is available for manual download.';
}

Future<bool> _launchExternalUrl(Uri uri) {
  return url_launcher.launchUrl(
    uri,
    mode: url_launcher.LaunchMode.externalApplication,
  );
}
