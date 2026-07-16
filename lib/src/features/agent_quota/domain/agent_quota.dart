import 'package:alera/src/features/settings/domain/alera_settings.dart';

enum AgentQuotaStatus { ok, stale, error, unavailable }

class AgentQuotaWindow {
  const AgentQuotaWindow({
    required this.label,
    required this.usedPercent,
    required this.windowMinutes,
    required this.resetsAt,
    required this.resetDescription,
  });

  factory AgentQuotaWindow.fromJson(Map<String, Object?> json) {
    return AgentQuotaWindow(
      label: (json['label'] as String?) ?? 'Quota',
      usedPercent: _doubleValue(json['usedPercent']),
      windowMinutes: json['windowMinutes'] as int?,
      resetsAt: _dateFromMillis(json['resetsAt']),
      resetDescription: json['resetDescription'] as String?,
    );
  }

  final String label;
  final double usedPercent;
  final int? windowMinutes;
  final DateTime? resetsAt;
  final String? resetDescription;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}

class AgentQuotaBucket {
  const AgentQuotaBucket({
    required this.name,
    required this.usedPercent,
    required this.windowMinutes,
    required this.resetsAt,
    required this.resetDescription,
  });

  factory AgentQuotaBucket.fromJson(Map<String, Object?> json) {
    return AgentQuotaBucket(
      name: (json['name'] as String?) ?? 'Quota',
      usedPercent: _doubleValue(json['usedPercent']),
      windowMinutes: json['windowMinutes'] as int?,
      resetsAt: _dateFromMillis(json['resetsAt']),
      resetDescription: json['resetDescription'] as String?,
    );
  }

  final String name;
  final double usedPercent;
  final int? windowMinutes;
  final DateTime? resetsAt;
  final String? resetDescription;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}

class AgentQuotaSnapshot {
  const AgentQuotaSnapshot({
    required this.provider,
    required this.accountId,
    required this.displayName,
    required this.status,
    required this.updatedAt,
    required this.error,
    required this.windows,
    required this.buckets,
  });

  factory AgentQuotaSnapshot.fromJson(Map<String, Object?> json) {
    return AgentQuotaSnapshot(
      provider: AgentQuotaProviderId.values.firstWhere(
        (provider) => provider.name == json['provider'],
      ),
      accountId: (json['accountId'] as String?) ?? 'default',
      displayName: (json['displayName'] as String?) ?? 'Default',
      status: AgentQuotaStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => AgentQuotaStatus.error,
      ),
      updatedAt:
          _dateFromMillis(json['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      error: json['error'] as String?,
      windows: _objectList(
        json['windows'],
      ).map(AgentQuotaWindow.fromJson).toList(growable: false),
      buckets: _objectList(
        json['buckets'],
      ).map(AgentQuotaBucket.fromJson).toList(growable: false),
    );
  }

  final AgentQuotaProviderId provider;
  final String accountId;
  final String displayName;
  final AgentQuotaStatus status;
  final DateTime updatedAt;
  final String? error;
  final List<AgentQuotaWindow> windows;
  final List<AgentQuotaBucket> buckets;

  String get key => '${provider.name}:$accountId';

  bool get hasUsage => windows.isNotEmpty || buckets.isNotEmpty;

  double? get remainingPercent {
    final values = <double>[
      for (final window in windows) window.remainingPercent,
      for (final bucket in buckets) bucket.remainingPercent,
    ];
    if (values.isEmpty) {
      return null;
    }
    values.sort();
    return values.first;
  }

  AgentQuotaSnapshot asStale(String? freshError) {
    return AgentQuotaSnapshot(
      provider: provider,
      accountId: accountId,
      displayName: displayName,
      status: AgentQuotaStatus.stale,
      updatedAt: updatedAt,
      error: freshError,
      windows: windows,
      buckets: buckets,
    );
  }
}

class AgentQuotaState {
  const AgentQuotaState({
    required this.hostId,
    required this.snapshots,
    required this.environment,
    required this.fetchedAt,
    this.error,
  });

  factory AgentQuotaState.empty(String hostId) {
    return AgentQuotaState(
      hostId: hostId,
      snapshots: const <AgentQuotaSnapshot>[],
      environment: const <String, bool>{},
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String hostId;
  final List<AgentQuotaSnapshot> snapshots;
  final Map<String, bool> environment;
  final DateTime fetchedAt;
  final String? error;

  AgentQuotaSnapshot? snapshot(
    AgentQuotaProviderId provider, {
    String accountId = 'default',
  }) {
    for (final snapshot in snapshots) {
      if (snapshot.provider == provider && snapshot.accountId == accountId) {
        return snapshot;
      }
    }
    return null;
  }
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

double _doubleValue(Object? value) {
  return switch (value) {
    final num number => number.toDouble().clamp(0, 100),
    final String raw => (double.tryParse(raw) ?? 0).clamp(0, 100),
    _ => 0,
  };
}

DateTime? _dateFromMillis(Object? value) {
  if (value is! int) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}
