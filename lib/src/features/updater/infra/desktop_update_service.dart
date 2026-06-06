import 'dart:io';

import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/update_archive.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef AleraUrlLauncher = Future<bool> Function(Uri uri);

class DesktopAleraUpdateService implements AleraUpdateService {
  DesktopAleraUpdateService({
    AleraUpdateConfig? config,
    http.Client? client,
    DesktopUpdater? desktopUpdater,
    PackageInfoLoader? loadPackageInfo,
    AleraUrlLauncher? launchUrl,
    String? platform,
  }) : config = config ?? AleraUpdateConfig.fromEnvironment(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _desktopUpdater = desktopUpdater ?? DesktopUpdater(),
       _loadPackageInfo = loadPackageInfo ?? PackageInfo.fromPlatform,
       _launchUrl = launchUrl ?? _launchExternalUrl,
       _platform = platform ?? Platform.operatingSystem;

  static const Set<String> _supportedPlatforms = <String>{
    'linux',
    'macos',
    'windows',
  };

  @override
  final AleraUpdateConfig config;

  final http.Client _client;
  final bool _ownsClient;
  final DesktopUpdater _desktopUpdater;
  final PackageInfoLoader _loadPackageInfo;
  final AleraUrlLauncher _launchUrl;
  final String _platform;

  @override
  Future<AleraUpdateCheckResult> checkForUpdates() async {
    if (!_supportedPlatforms.contains(_platform)) {
      return AleraUpdateCheckResult(
        message: 'Desktop updates are not available on $_platform.',
      );
    }
    if (config.canAutoInstall &&
        config.channel == AleraUpdateChannel.rc &&
        !config.signedRelease) {
      return _checkWithDesktopUpdater();
    }
    return _checkManually();
  }

  Future<AleraUpdateCheckResult> _checkWithDesktopUpdater() async {
    final item = await _desktopUpdater.versionCheck(
      appArchiveUrl: config.archiveUrl.toString(),
    );
    if (item == null) {
      return const AleraUpdateCheckResult(message: 'Alera is up to date.');
    }
    final update = _fromItemModel(item);
    return AleraUpdateCheckResult(
      latest: update,
      autoInstallAllowed: true,
      message: 'Update ${update.version} is ready to install.',
    );
  }

  Future<AleraUpdateCheckResult> _checkManually() async {
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
    final latest = archive.latestFor(
      platform: _platform,
      currentBuildNumber: currentBuild,
      channel: config.channel,
    );

    if (latest == null) {
      return const AleraUpdateCheckResult(message: 'Alera is up to date.');
    }

    if (_platform == 'linux') {
      return AleraUpdateCheckResult(
        latest: latest,
        message: _linuxUpdateMessage(config.channel, latest),
      );
    }

    return AleraUpdateCheckResult(
      latest: latest,
      autoInstallAllowed: config.canAutoInstall && archive.schemaVersion == 1,
      message: config.autoInstallEnabled
          ? _manualInstallBlockedMessage(archive)
          : 'Update ${latest.version} is available for manual download.',
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

    final item = await _desktopUpdater.versionCheck(
      appArchiveUrl: config.archiveUrl.toString(),
    );
    if (item == null) {
      throw StateError('No update is available.');
    }

    final stream = await _desktopUpdater.updateApp(
      remoteUpdateFolder: item.url,
      changedFiles: item.changedFiles ?? const <FileHashModel?>[],
    );
    await for (final updateProgress in stream) {
      final totalBytes = updateProgress.totalBytes;
      if (totalBytes <= 0) {
        continue;
      }
      onProgress?.call(updateProgress.receivedBytes / totalBytes);
    }
    onProgress?.call(1);
  }

  @override
  Future<void> openDownloadPage(AleraUpdateInfo? update) async {
    await _launchUrl(config.releasePageUrl);
  }

  @override
  Future<void> restartApp() {
    return _desktopUpdater.restartApp();
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

String _linuxUpdateMessage(AleraUpdateChannel channel, AleraUpdateInfo update) {
  if (channel == AleraUpdateChannel.stable &&
      (update.installerKind == 'deb' || update.installerKind == 'rpm')) {
    return 'Update ${update.version} is available through the Linux package repository.';
  }
  return 'Update ${update.version} is available for manual download.';
}

String _manualInstallBlockedMessage(AleraUpdateArchive archive) {
  if (archive.schemaVersion >= 2) {
    return 'Update manifest is signed; automatic installer apply is pending for this artifact type.';
  }
  return 'Automatic installation is blocked until stable releases are signed.';
}

AleraUpdateInfo _fromItemModel(ItemModel item) {
  return AleraUpdateInfo(
    version: item.version,
    shortVersion: item.shortVersion,
    date: item.date,
    mandatory: item.mandatory,
    url: Uri.parse(item.url),
    platform: item.platform,
    changes: [for (final change in item.changes) change.message],
  );
}

Future<bool> _launchExternalUrl(Uri uri) {
  return url_launcher.launchUrl(
    uri,
    mode: url_launcher.LaunchMode.externalApplication,
  );
}
