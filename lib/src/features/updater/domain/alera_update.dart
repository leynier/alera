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

class AleraUpdateConfig {
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

  final Uri archiveUrl;
  final Uri releasePageUrl;
  final AleraUpdateChannel channel;
  final bool autoInstallEnabled;
  final bool signedRelease;

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
    return AleraUpdateConfig(
      archiveUrl: archiveUrl ?? defaultArchiveUrl,
      releasePageUrl: releasePageUrl ?? defaultReleasePageUrl,
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
}

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

class AleraUpdateInfo {
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
  final Uri url;
  final String platform;
  final List<String> changes;

  bool get isPrerelease => version.contains('-');
}

class AleraUpdateState {
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

  final AleraUpdateStatus status;
  final AleraUpdateConfig config;
  final AleraUpdateInfo? latest;
  final String? message;
  final double progress;

  bool get isBusy {
    return status == AleraUpdateStatus.checking ||
        status == AleraUpdateStatus.downloading;
  }

  AleraUpdateState copyWith({
    AleraUpdateStatus? status,
    AleraUpdateConfig? config,
    AleraUpdateInfo? latest,
    String? message,
    double? progress,
    bool clearLatest = false,
    bool clearMessage = false,
  }) {
    return AleraUpdateState(
      status: status ?? this.status,
      config: config ?? this.config,
      latest: clearLatest ? null : latest ?? this.latest,
      message: clearMessage ? null : message ?? this.message,
      progress: progress ?? this.progress,
    );
  }
}
