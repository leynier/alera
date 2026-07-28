import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_artifact_selector.dart';
import 'package:alera/src/features/updater/infra/desktop_update_handoff.dart';
import 'package:alera/src/features/updater/infra/desktop_update_stager.dart';
import 'package:alera/src/features/updater/infra/update_archive.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/process/rust_process_runner.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef AleraUrlLauncher = Future<bool> Function(Uri uri);

class DesktopAleraUpdateService implements AleraUpdateService {
  DesktopAleraUpdateService({
    AleraUpdateConfig? config,
    http.Client? client,
    PackageInfoLoader? loadPackageInfo,
    AleraUrlLauncher? launchUrl,
    String? platform,
    DesktopUpdateArtifactPreferences? loadArtifactPreferences,
    AleraDesktopUpdateStager? stager,
    AleraDesktopUpdateHandoff? handoff,
    ProcessRunner? processRunner,
    String? resolvedExecutable,
    int? processId,
    AleraAppExit? exitApp,
  }) : config = config ?? AleraUpdateConfig.fromEnvironment(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _loadPackageInfo = loadPackageInfo ?? PackageInfo.fromPlatform,
       _launchUrl = launchUrl ?? _launchExternalUrl,
       _platform = platform ?? Platform.operatingSystem,
       _loadArtifactPreferences =
           loadArtifactPreferences ?? loadDesktopUpdateArtifactPreferences {
    _stager =
        stager ?? DesktopUpdateStager(client: _client, platform: _platform);
    _handoff =
        handoff ??
        DesktopUpdateHandoff(
          processRunner: processRunner ?? const RustProcessRunner(),
          platform: _platform,
          resolvedExecutable: resolvedExecutable,
          processId: processId,
          exitApp: exitApp,
        );
  }

  static const Set<String> _supportedPlatforms = <String>{
    'linux',
    'macos',
    'windows',
  };

  @override
  final AleraUpdateConfig config;

  final http.Client _client;
  final bool _ownsClient;
  final PackageInfoLoader _loadPackageInfo;
  final AleraUrlLauncher _launchUrl;
  final String _platform;
  final DesktopUpdateArtifactPreferences _loadArtifactPreferences;
  late final AleraDesktopUpdateStager _stager;
  late final AleraDesktopUpdateHandoff _handoff;
  StagedDesktopUpdate? _stagedUpdate;

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    if (!_supportedPlatforms.contains(_platform)) {
      return AleraUpdateCheckResult(
        message: 'Desktop updates are not available on $_platform.',
      );
    }
    final response = await _client.get(config.archiveUrl);
    if (response.statusCode == 404) {
      return const AleraUpdateCheckResult(
        message: 'No update index is published yet.',
      );
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download app archive (${response.statusCode}).',
        uri: config.archiveUrl,
      );
    }

    final packageInfo = await _loadPackageInfo();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
    final archive = config.signedRelease
        ? await AleraUpdateArchive.fromSignedJsonString(
            response.body,
            publicKeyBase64: config.manifestPublicKey,
          )
        : AleraUpdateArchive.fromJsonString(response.body);
    final artifactPreferences = await _loadArtifactPreferences(
      _platform,
      config.channel,
    );
    final latest = archive.latestFor(
      platform: _platform,
      currentBuildNumber: currentBuild,
      channel: config.channel,
      preferredInstallerKinds: artifactPreferences,
    );

    if (latest == null) {
      final newestPlatformUpdate = archive.latestFor(
        platform: _platform,
        currentBuildNumber: currentBuild,
        channel: config.channel,
      );
      if (newestPlatformUpdate != null) {
        return AleraUpdateCheckResult(
          message: _incompatibleArtifactMessage(_platform),
        );
      }
      return const AleraUpdateCheckResult(message: 'Alera is up to date.');
    }

    final autoInstallAllowed =
        config.canAutoInstall &&
        archive.schemaVersion >= 2 &&
        latest.sha256 != null &&
        latest.size != null &&
        _supportsAutomaticInstall(latest);
    if (autoInstallAllowed) {
      return AleraUpdateCheckResult(
        latest: latest,
        autoInstallAllowed: true,
        message: 'Update ${latest.version} is ready to install.',
      );
    }

    return AleraUpdateCheckResult(
      latest: latest,
      message: _manualUpdateMessage(config, archive, latest),
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
    if (update.platform == 'linux') {
      throw StateError(
        'Automatic Linux updates are disabled. Install the deb or rpm '
        'package through apt, dnf, or the configured package repository.',
      );
    }
    if (!_supportsAutomaticInstall(update)) {
      throw StateError(
        'Automatic installation does not support '
        '${update.platform} ${update.installerKind} artifacts.',
      );
    }

    final previousStage = _stagedUpdate;
    _stagedUpdate = null;
    if (previousStage != null) {
      await previousStage.delete();
    }
    _stagedUpdate = await _stager.stage(update, onProgress: onProgress);
  }

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {
    final launched = await _launchUrl(config.downloadPageUrlFor(update));
    if (!launched) {
      throw StateError('The release download page could not be opened.');
    }
  }

  @override
  Future<void> restartApp() async {
    final stagedUpdate = _stagedUpdate;
    if (stagedUpdate == null) {
      throw StateError('No verified update is ready to install.');
    }
    await _handoff.applyAndRestart(stagedUpdate);
    _stagedUpdate = null;
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
    final stagedUpdate = _stagedUpdate;
    _stagedUpdate = null;
    if (stagedUpdate != null) {
      unawaited(stagedUpdate.delete());
    }
  }
}

const Set<String> _autoInstallKinds = <String>{'tar.gz', 'deb', 'rpm'};

bool _supportsAutomaticInstall(AleraUpdateInfo update) {
  if (update.platform == 'linux') {
    return false;
  }
  if (!_autoInstallKinds.contains(update.installerKind)) {
    return false;
  }
  return true;
}

String _manualUpdateMessage(
  AleraUpdateConfig config,
  AleraUpdateArchive archive,
  AleraUpdateInfo update,
) {
  if (update.platform == 'linux' &&
      update.installerKind != 'deb' &&
      update.installerKind != 'rpm') {
    return 'Linux tarball updates are unsupported. Install the deb or rpm '
        'package through apt, dnf, or the configured package repository.';
  }
  if (update.platform == 'linux' &&
      config.channel == AleraUpdateChannel.stable &&
      (update.installerKind == 'deb' || update.installerKind == 'rpm')) {
    return 'Update ${update.version} is available through the Linux package repository.';
  }
  if (config.autoInstallEnabled && archive.schemaVersion < 2) {
    return 'Automatic installation requires a signed update artifact with integrity metadata.';
  }
  return 'Update ${update.version} is available for manual download.';
}

String _platformLabel(String platform) {
  return switch (platform) {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    _ => platform,
  };
}

String _incompatibleArtifactMessage(String platform) {
  if (platform == 'linux') {
    return 'No compatible Linux package is available for this distribution. '
        'See ${AleraUpdateConfig.installGuideUrl} for supported distributions.';
  }
  return 'No compatible ${_platformLabel(platform)} update artifact '
      'is available for this installation.';
}

Future<bool> _launchExternalUrl(Uri uri) {
  return url_launcher.launchUrl(
    uri,
    mode: url_launcher.LaunchMode.externalApplication,
  );
}
