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
  });

  static final Uri defaultArchiveUrl = Uri.parse(
    'https://leynier.github.io/alera/app-archive.json',
  );
  static final Uri defaultReleasePageUrl = Uri.parse(
    'https://github.com/leynier/alera/releases',
  );

  @MappableField(hook: _UriStringHook())
  final Uri archiveUrl;
  @MappableField(hook: _UriStringHook())
  final Uri releasePageUrl;
  final AleraUpdateChannel channel;
  final bool autoInstallEnabled;
  final bool signedRelease;

  static AleraUpdateConfig _resolvedEnvironmentConfig({
    required Uri? archiveUrl,
    required Uri? releasePageUrl,
    required AleraUpdateChannel channel,
    required bool autoInstallEnabled,
    required bool signedRelease,
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
    );
  }

  bool get canAutoInstall {
    return autoInstallEnabled &&
        (signedRelease || channel == AleraUpdateChannel.rc);
  }

  factory AleraUpdateConfig.fromEnvironment() {
    final archiveUrl = Uri.tryParse(
      const String.fromEnvironment(
        'ALERA_UPDATE_ARCHIVE_URL',
        defaultValue: 'https://leynier.github.io/alera/app-archive.json',
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
      autoInstallEnabled: const bool.fromEnvironment(
        'ALERA_UPDATE_AUTO_INSTALL_ENABLED',
      ),
      signedRelease: const bool.fromEnvironment('ALERA_SIGNED_RELEASE'),
    );
  }

  factory AleraUpdateConfig.fromJson(Map<String, Object?> json) =>
      AleraUpdateConfigMapper.fromMap(Map<String, dynamic>.from(json));
}

@visibleForTesting
Uri resolveUpdateConfigUriForTesting(Uri? value, Uri fallback) =>
    value ?? fallback;

@MappableEnum()
enum AleraUpdateStatus {
  idle,
  checking,
  notAvailable,
  manualDownloadRequired,
  available,
  downloading,
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
  });

  final String version;
  final int shortVersion;
  final String date;
  final bool mandatory;
  @MappableField(hook: _UriStringHook())
  final Uri url;
  final String platform;
  final List<String> changes;

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
        status == AleraUpdateStatus.downloading;
  }
}
