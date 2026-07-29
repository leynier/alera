import 'package:alera_mobile/src/core/json_payload_fields.dart';

class QuotaSnapshotState {
  const QuotaSnapshotState({
    required this.snapshots,
    required this.environment,
    required this.fetchedAt,
  });

  factory QuotaSnapshotState.fromJson(Map<String, Object?> json) {
    return QuotaSnapshotState(
      snapshots: <QuotaSnapshot>[
        for (final item in json.objectList('snapshots'))
          if (item is Map) QuotaSnapshot.fromJson(asJsonMap(item)),
      ],
      environment: <String, bool>{
        for (final entry in json.mapValue('environment').entries)
          if (entry.value is bool) entry.key: entry.value! as bool,
      },
      fetchedAt: DateTime.now().toUtc(),
    );
  }

  final List<QuotaSnapshot> snapshots;
  final Map<String, bool> environment;
  final DateTime fetchedAt;
}

class QuotaSnapshot {
  const QuotaSnapshot({
    required this.provider,
    required this.accountId,
    required this.displayName,
    required this.status,
    required this.updatedAt,
    required this.error,
    required this.windows,
    required this.buckets,
    this.rateLimitResetCredits,
  });

  factory QuotaSnapshot.fromJson(Map<String, Object?> json) {
    return QuotaSnapshot(
      provider: json['provider'] as String? ?? 'unknown',
      accountId: json['accountId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      status: json['status'] as String? ?? 'error',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int? ?? 0,
        isUtc: true,
      ),
      error: json['error'] as String?,
      windows: <QuotaMeter>[
        for (final item in json.objectList('windows'))
          if (item is Map)
            QuotaMeter.fromJson(asJsonMap(item), labelKey: 'label'),
      ],
      buckets: <QuotaMeter>[
        for (final item in json.objectList('buckets'))
          if (item is Map)
            QuotaMeter.fromJson(asJsonMap(item), labelKey: 'name'),
      ],
      rateLimitResetCredits: switch (json['rateLimitResetCredits']) {
        final Map value => CodexResetCredits.fromJson(asJsonMap(value)),
        _ => null,
      },
    );
  }

  final String provider;
  final String accountId;
  final String displayName;
  final String status;
  final DateTime updatedAt;
  final String? error;
  final List<QuotaMeter> windows;
  final List<QuotaMeter> buckets;
  final CodexResetCredits? rateLimitResetCredits;
}

class CodexResetCredits {
  const CodexResetCredits({
    required this.availableCount,
    required this.nextExpiresAt,
    required this.offerRevision,
    required this.canConsume,
  });

  factory CodexResetCredits.fromJson(Map<String, Object?> json) {
    final expiry = json['nextExpiresAt'] as int?;
    return CodexResetCredits(
      availableCount: switch (json['availableCount']) {
        final int count when count > 0 => count,
        _ => 0,
      },
      nextExpiresAt: expiry == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiry, isUtc: true),
      offerRevision: json['offerRevision'] as String? ?? '',
      canConsume: json['canConsume'] == true,
    );
  }

  final int availableCount;
  final DateTime? nextExpiresAt;
  final String offerRevision;
  final bool canConsume;
}

class CodexResetConsumeResult {
  const CodexResetConsumeResult({
    required this.status,
    required this.outcome,
    required this.reason,
    required this.snapshot,
  });

  factory CodexResetConsumeResult.fromJson(Map<String, Object?> json) {
    final rawSnapshot = json['snapshot'];
    if (rawSnapshot is! Map) {
      throw const FormatException('Codex reset response missing snapshot.');
    }
    return CodexResetConsumeResult(
      status: json['status'] as String? ?? 'rejected',
      outcome: json['outcome'] as String?,
      reason: json['reason'] as String?,
      snapshot: QuotaSnapshot.fromJson(asJsonMap(rawSnapshot)),
    );
  }

  final String status;
  final String? outcome;
  final String? reason;
  final QuotaSnapshot snapshot;
}

class QuotaMeter {
  const QuotaMeter({
    required this.label,
    required this.usedPercent,
    required this.resetsAt,
    required this.resetDescription,
  });

  factory QuotaMeter.fromJson(
    Map<String, Object?> json, {
    required String labelKey,
  }) {
    final used = switch (json['usedPercent']) {
      final num value => value.toDouble(),
      _ => 0.0,
    };
    final resetMillis = json['resetsAt'] as int?;
    return QuotaMeter(
      label: json[labelKey] as String? ?? 'Quota',
      usedPercent: used.clamp(0, 100),
      resetsAt: resetMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(resetMillis, isUtc: true),
      resetDescription: json['resetDescription'] as String?,
    );
  }

  final String label;
  final double usedPercent;
  final DateTime? resetsAt;
  final String? resetDescription;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}
