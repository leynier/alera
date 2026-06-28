enum SshAuthKind {
  password,
  key,
  agent;

  static SshAuthKind parse(Object? value) {
    return switch (value) {
      'key' => SshAuthKind.key,
      'agent' => SshAuthKind.agent,
      _ => SshAuthKind.password,
    };
  }
}

enum SshBootstrapStatus {
  notInstalled,
  planned,
  installing,
  installed,
  failed,
  cancelled;

  static SshBootstrapStatus parse(Object? value) {
    return switch (value) {
      'planned' => SshBootstrapStatus.planned,
      'installing' => SshBootstrapStatus.installing,
      'installed' => SshBootstrapStatus.installed,
      'failed' => SshBootstrapStatus.failed,
      'cancelled' => SshBootstrapStatus.cancelled,
      _ => SshBootstrapStatus.notInstalled,
    };
  }

  bool get isBusy => this == SshBootstrapStatus.installing;
}

class SshTarget {
  const SshTarget({
    required this.id,
    required this.alias,
    required this.host,
    required this.port,
    required this.username,
    required this.authKind,
    required this.createdAt,
    required this.updatedAt,
    this.platform,
    this.arch,
    this.lastStatus,
    this.installDir,
    this.runtimeVersion,
    this.runtimePlatform,
    this.runtimeArch,
    this.bootstrapStatus = SshBootstrapStatus.notInstalled,
    this.lastBootstrapAt,
    this.lastCheckedAt,
    this.lastError,
  });

  factory SshTarget.fromJson(Map<String, Object?> json) {
    return SshTarget(
      id: _requiredString(json, 'id'),
      alias: _requiredString(json, 'alias'),
      host: _requiredString(json, 'host'),
      port: _intValue(json['port'], fallback: 22),
      username: _requiredString(json, 'username'),
      platform: _optionalString(json['platform']),
      arch: _optionalString(json['arch']),
      authKind: SshAuthKind.parse(json['authKind']),
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
      lastStatus: _optionalString(json['lastStatus']),
      installDir: _optionalString(json['installDir']),
      runtimeVersion: _optionalString(json['runtimeVersion']),
      runtimePlatform: _optionalString(json['runtimePlatform']),
      runtimeArch: _optionalString(json['runtimeArch']),
      bootstrapStatus: SshBootstrapStatus.parse(json['bootstrapStatus']),
      lastBootstrapAt: _optionalDateTime(json['lastBootstrapAt']),
      lastCheckedAt: _optionalDateTime(json['lastCheckedAt']),
      lastError: _optionalString(json['lastError']),
    );
  }

  final String id;
  final String alias;
  final String host;
  final int port;
  final String username;
  final String? platform;
  final String? arch;
  final SshAuthKind authKind;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastStatus;
  final String? installDir;
  final String? runtimeVersion;
  final String? runtimePlatform;
  final String? runtimeArch;
  final SshBootstrapStatus bootstrapStatus;
  final DateTime? lastBootstrapAt;
  final DateTime? lastCheckedAt;
  final String? lastError;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'alias': alias,
      'host': host,
      'port': port,
      'username': username,
      'platform': platform,
      'arch': arch,
      'authKind': authKind.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'lastStatus': lastStatus,
      'installDir': installDir,
      'runtimeVersion': runtimeVersion,
      'runtimePlatform': runtimePlatform,
      'runtimeArch': runtimeArch,
      'bootstrapStatus': bootstrapStatus.name,
      'lastBootstrapAt': lastBootstrapAt?.toUtc().toIso8601String(),
      'lastCheckedAt': lastCheckedAt?.toUtc().toIso8601String(),
      'lastError': lastError,
    };
  }

  SshTarget copyWith({
    String? alias,
    String? host,
    int? port,
    String? username,
    String? platform,
    String? arch,
    SshAuthKind? authKind,
    String? installDir,
  }) {
    final now = DateTime.now().toUtc();
    return SshTarget(
      id: id,
      alias: alias ?? this.alias,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      platform: platform ?? this.platform,
      arch: arch ?? this.arch,
      authKind: authKind ?? this.authKind,
      createdAt: createdAt,
      updatedAt: now,
      lastStatus: lastStatus,
      installDir: installDir ?? this.installDir,
      runtimeVersion: runtimeVersion,
      runtimePlatform: runtimePlatform,
      runtimeArch: runtimeArch,
      bootstrapStatus: bootstrapStatus,
      lastBootstrapAt: lastBootstrapAt,
      lastCheckedAt: lastCheckedAt,
      lastError: lastError,
    );
  }
}

class SshTargetBootstrapPlan {
  const SshTargetBootstrapPlan({
    required this.targetId,
    required this.platform,
    required this.arch,
    required this.installDir,
    required this.channel,
    required this.artifactSource,
    required this.trust,
    required this.steps,
    this.version,
  });

  factory SshTargetBootstrapPlan.fromJson(Map<String, Object?> json) {
    return SshTargetBootstrapPlan(
      targetId: _requiredString(json, 'targetId'),
      platform: _requiredString(json, 'platform'),
      arch: _requiredString(json, 'arch'),
      installDir: _requiredString(json, 'installDir'),
      channel: _requiredString(json, 'channel'),
      artifactSource: _requiredString(json, 'artifactSource'),
      trust: _requiredString(json, 'trust'),
      version: _optionalString(json['version']),
      steps: <String>[
        for (final step in (json['steps'] as List? ?? const <Object?>[]))
          if (step is String) step,
      ],
    );
  }

  final String targetId;
  final String platform;
  final String arch;
  final String installDir;
  final String channel;
  final String artifactSource;
  final String trust;
  final String? version;
  final List<String> steps;
}

class SshTargetBootstrapJob {
  const SshTargetBootstrapJob({
    required this.jobId,
    required this.targetId,
    required this.status,
  });

  factory SshTargetBootstrapJob.fromJson(Map<String, Object?> json) {
    return SshTargetBootstrapJob(
      jobId: _requiredString(json, 'jobId'),
      targetId: _requiredString(json, 'targetId'),
      status: SshBootstrapStatus.parse(json['status']),
    );
  }

  final String jobId;
  final String targetId;
  final SshBootstrapStatus status;
}

class SshTargetBootstrapProgress {
  const SshTargetBootstrapProgress({
    required this.jobId,
    required this.targetId,
    required this.status,
    required this.stage,
    required this.message,
    this.error,
  });

  factory SshTargetBootstrapProgress.fromJson(Map<String, Object?> json) {
    return SshTargetBootstrapProgress(
      jobId: _requiredString(json, 'jobId'),
      targetId: _requiredString(json, 'targetId'),
      status: SshBootstrapStatus.parse(json['status']),
      stage: _requiredString(json, 'stage'),
      message: _requiredString(json, 'message'),
      error: _optionalString(json['error']),
    );
  }

  final String jobId;
  final String targetId;
  final SshBootstrapStatus status;
  final String stage;
  final String message;
  final String? error;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

int _intValue(Object? value, {required int fallback}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

DateTime _dateTime(Object? value) {
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw const FormatException('date must be an ISO-8601 string.');
}

DateTime? _optionalDateTime(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value).toUtc();
  }
  return null;
}
