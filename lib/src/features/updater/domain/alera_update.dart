import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:meta/meta.dart';

part 'alera_update.mapper.dart';

@MappableEnum()
enum AleraUpdateChannel {
  stable,
  rc;

  bool get includesPrereleases => this == AleraUpdateChannel.rc;

  static AleraUpdateChannel parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'rc' || 'release-candidate' => AleraUpdateChannel.rc,
      _ => AleraUpdateChannel.stable,
    };
  }
}

class _UriStringHook extends MappingHook {
  const _UriStringHook();

  @override
  Object? beforeDecode(Object? value) {
    if (value is String) {
      return Uri.parse(value);
    }
    return value;
  }

  @override
  Object? beforeEncode(Object? value) {
    if (value is Uri) {
      return value.toString();
    }
    return value;
  }
}

@MappableClass()
class AleraUpdateConfig with AleraUpdateConfigMappable {
  const AleraUpdateConfig({
    required this.archiveUrl,
    required this.releasePageUrl,
    required this.channel,
    required this.autoInstallEnabled,
    required this.signedRelease,
    this.manifestPublicKey = '',
    this.manifestPublicKeyId = 'alera-release-v1',
  });

  static final Uri defaultArchiveUrl = Uri.parse(
    'https://updates.alera.build/updates/stable/app-archive.json',
  );
  static final Uri defaultReleasePageUrl = Uri.parse(
    'https://github.com/leynier/alera/releases',
  );
  static final Uri installGuideUrl = Uri.parse('https://alera.build/download');

  @MappableField(hook: _UriStringHook())
  final Uri archiveUrl;
  @MappableField(hook: _UriStringHook())
  final Uri releasePageUrl;
  final AleraUpdateChannel channel;
  final bool autoInstallEnabled;
  final bool signedRelease;
  final String manifestPublicKey;
  final String manifestPublicKeyId;

  static AleraUpdateConfig _resolvedEnvironmentConfig({
    required Uri? archiveUrl,
    required Uri? releasePageUrl,
    required AleraUpdateChannel channel,
    required bool autoInstallEnabled,
    required bool signedRelease,
    required String manifestPublicKey,
    required String manifestPublicKeyId,
  }) {
    return AleraUpdateConfig(
      archiveUrl: resolveUpdateConfigUriForTesting(
        archiveUrl,
        defaultArchiveUrl,
      ),
      releasePageUrl: resolveUpdateConfigUriForTesting(
        releasePageUrl,
        defaultReleasePageUrl,
      ),
      channel: channel,
      autoInstallEnabled: autoInstallEnabled,
      signedRelease: signedRelease,
      manifestPublicKey: manifestPublicKey,
      manifestPublicKeyId: manifestPublicKeyId,
    );
  }

  bool get canAutoInstall {
    return autoInstallEnabled &&
        ((signedRelease && manifestPublicKey.trim().isNotEmpty) ||
            channel == AleraUpdateChannel.rc);
  }

  /// Resolves the manual-download page for an available update.
  ///
  /// Release builds bake [releasePageUrl] to the *installed* version's GitHub
  /// tag page (`.../releases/tag/vX.Y.Z`). When a newer update is detected,
  /// open that update's tag page instead of the baked current-version URL.
  ///
  /// An update a package manager can install is the exception: sending someone
  /// to download a loose `.deb` is the opposite of what the update copy tells
  /// them to do, so those open the install guide instead.
  Uri downloadPageUrlFor(AleraUpdateInfo? update) {
    if (update == null) {
      return releasePageUrl;
    }
    if (linuxPackageUpgradeCommand(update: update, channel: channel) != null) {
      return installGuideUrl;
    }
    return resolveAleraReleaseTagPageUrl(
      releasePageUrl: releasePageUrl,
      version: update.version,
    );
  }

  factory AleraUpdateConfig.fromEnvironment() {
    final archiveUrl = Uri.tryParse(
      const String.fromEnvironment(
        'ALERA_UPDATE_ARCHIVE_URL',
        defaultValue:
            'https://updates.alera.build/updates/stable/app-archive.json',
      ),
    );
    final releasePageUrl = Uri.tryParse(
      const String.fromEnvironment(
        'ALERA_RELEASE_PAGE_URL',
        defaultValue: 'https://github.com/leynier/alera/releases',
      ),
    );
    return _resolvedEnvironmentConfig(
      archiveUrl: archiveUrl,
      releasePageUrl: releasePageUrl,
      channel: AleraUpdateChannel.parse(
        const String.fromEnvironment(
          'ALERA_UPDATE_CHANNEL',
          defaultValue: 'stable',
        ),
      ),
      autoInstallEnabled: effectiveAutoInstallEnabled(
        const bool.fromEnvironment('ALERA_UPDATE_AUTO_INSTALL_ENABLED'),
      ),
      signedRelease: const bool.fromEnvironment('ALERA_SIGNED_RELEASE'),
      manifestPublicKey: const String.fromEnvironment(
        'ALERA_UPDATE_MANIFEST_PUBLIC_KEY',
      ),
      manifestPublicKeyId: const String.fromEnvironment(
        'ALERA_UPDATE_MANIFEST_PUBLIC_KEY_ID',
        defaultValue: 'alera-release-v1',
      ),
    );
  }

  factory AleraUpdateConfig.fromJson(Map<String, Object?> json) =>
      AleraUpdateConfigMapper.fromMap(Map<String, dynamic>.from(json));
}

@visibleForTesting
Uri resolveUpdateConfigUriForTesting(Uri? value, Uri fallback) =>
    value ?? fallback;

/// The command that upgrades an installed Alera package in place.
///
/// Returns null whenever a package manager cannot deliver [update]: other
/// platforms, Linux tarballs, and release candidates, which are published as
/// GitHub assets but never to the stable package repositories.
String? linuxPackageUpgradeCommand({
  required AleraUpdateInfo? update,
  required AleraUpdateChannel channel,
}) {
  if (update == null ||
      update.platform != 'linux' ||
      channel != AleraUpdateChannel.stable) {
    return null;
  }
  return switch (update.installerKind) {
    'deb' => 'sudo apt-get update && sudo apt-get install --only-upgrade alera',
    'rpm' => 'sudo dnf upgrade alera',
    _ => null,
  };
}

/// The command that upgrades Alera through whatever package manager owns it.
///
/// Subsumes [linuxPackageUpgradeCommand]: on Linux the manager is inferred from
/// the artifact Alera would have downloaded, everywhere else from where the
/// running executable lives. Release candidates return null on every platform,
/// because they are published as GitHub assets and never reach a package
/// manager, so telling someone to run an upgrade would only report no change.
String? packageManagerUpgradeCommand({
  required AleraUpdateInfo? update,
  required AleraUpdateChannel channel,
  required PackageInstallMethod installMethod,
}) {
  if (channel != AleraUpdateChannel.stable) {
    return null;
  }
  return switch (installMethod) {
    PackageInstallMethod.homebrewCask => 'brew upgrade --cask alera',
    PackageInstallMethod.scoop => 'scoop update alera',
    PackageInstallMethod.chocolatey => 'choco upgrade alera -y',
    PackageInstallMethod.unmanaged => linuxPackageUpgradeCommand(
      update: update,
      channel: channel,
    ),
  };
}

/// Builds a GitHub-style release tag URL for [version] under [releasePageUrl].
///
/// Accepts either the releases list (`.../releases`) or a baked tag page
/// (`.../releases/tag/v0.9.0`) and returns `.../releases/tag/v{version}`.
@visibleForTesting
Uri resolveAleraReleaseTagPageUrl({
  required Uri releasePageUrl,
  required String version,
}) {
  final trimmed = version.trim();
  if (trimmed.isEmpty) {
    return releasePageUrl;
  }
  final tag = trimmed.startsWith('v') ? trimmed : 'v$trimmed';
  final segments = releasePageUrl.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  final releasesIndex = segments.indexOf('releases');
  if (releasesIndex < 0) {
    return releasePageUrl.replace(
      pathSegments: <String>[...segments, 'tag', tag],
    );
  }
  return releasePageUrl.replace(
    pathSegments: <String>[
      ...segments.sublist(0, releasesIndex + 1),
      'tag',
      tag,
    ],
  );
}

@MappableEnum()
enum AleraUpdateStatus {
  idle,
  checking,
  notAvailable,
  manualDownloadRequired,
  available,
  downloading,
  applying,
  downloaded,
  error,
}

@MappableClass()
class AleraUpdateInfo with AleraUpdateInfoMappable {
  const AleraUpdateInfo({
    required this.version,
    required this.shortVersion,
    required this.date,
    required this.mandatory,
    required this.url,
    required this.platform,
    required this.changes,
    this.installerKind = 'directory',
    this.sha256,
    this.size,
    this.signatureBundleUrl,
    this.provenanceUrl,
  });

  final String version;
  final int shortVersion;
  final String date;
  final bool mandatory;
  @MappableField(hook: _UriStringHook())
  final Uri url;
  final String platform;
  final List<String> changes;
  final String installerKind;
  final String? sha256;
  final int? size;
  @MappableField(hook: _UriStringHook())
  final Uri? signatureBundleUrl;
  @MappableField(hook: _UriStringHook())
  final Uri? provenanceUrl;

  bool get isPrerelease => version.contains('-');

  factory AleraUpdateInfo.fromJson(Map<String, Object?> json) =>
      AleraUpdateInfoMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class AleraUpdateState with AleraUpdateStateMappable {
  const AleraUpdateState({
    required this.status,
    required this.config,
    this.latest,
    this.message,
    this.progress = 0,
  });

  factory AleraUpdateState.idle(AleraUpdateConfig config) {
    return AleraUpdateState(status: AleraUpdateStatus.idle, config: config);
  }

  factory AleraUpdateState.fromJson(Map<String, Object?> json) =>
      AleraUpdateStateMapper.fromMap(Map<String, dynamic>.from(json));

  final AleraUpdateStatus status;
  final AleraUpdateConfig config;
  final AleraUpdateInfo? latest;
  final String? message;
  final double progress;

  bool get isBusy {
    return status == AleraUpdateStatus.checking ||
        status == AleraUpdateStatus.downloading ||
        status == AleraUpdateStatus.applying;
  }
}
