import 'package:alera_mobile/src/core/json_payload_fields.dart';

class const QuotaSnapshotState({
  required final List<QuotaSnapshot> snapshots,
  required final Map<String, bool> environment,
  required final DateTime fetchedAt,
}) {
  factory fromJson(Map<String, Object?> json) {
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
}

class const QuotaSnapshot({
  required final String provider,
  required final String accountId,
  required final String displayName,
  required final String status,
  required final DateTime updatedAt,
  required final String? error,
  required final List<QuotaMeter> windows,
  required final List<QuotaMeter> buckets,
  final CodexResetCredits? rateLimitResetCredits,
  final String? dataQuality,
  final List<QuotaAmount> amounts = const <QuotaAmount>[],
}) {
  factory fromJson(Map<String, Object?> json) {
    return QuotaSnapshot(
      provider: json['provider'] as String? ?? 'unknown',
      accountId: json['accountId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      status: json['status'] as String? ?? 'error',
      updatedAt: .fromMillisecondsSinceEpoch(
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
      dataQuality: json['dataQuality'] as String?,
      amounts: <QuotaAmount>[
        for (final item in json.objectList('amounts'))
          if (item is Map) QuotaAmount.fromJson(asJsonMap(item)),
      ],
    );
  }
}

class const CodexResetCredits({
  required final int availableCount,
  required final DateTime? nextExpiresAt,
  required final String offerRevision,
  required final bool canConsume,
}) {
  factory fromJson(Map<String, Object?> json) {
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
}

class const CodexResetConsumeResult({
  required final String status,
  required final String? outcome,
  required final String? reason,
  required final QuotaSnapshot snapshot,
}) {
  factory fromJson(Map<String, Object?> json) {
    final rawSnapshot = json['snapshot'];
    if (rawSnapshot is! Map) {
      throw const FormatException('Codex reset response missing snapshot.');
    }
    return CodexResetConsumeResult(
      status: json['status'] as String? ?? 'rejected',
      outcome: json['outcome'] as String?,
      reason: json['reason'] as String?,
      snapshot: .fromJson(asJsonMap(rawSnapshot)),
    );
  }
}

class const QuotaMeter({
  required final String label,
  required final double usedPercent,
  required final DateTime? resetsAt,
  required final String? resetDescription,
  final String? displayValue,
}) {
  factory fromJson(Map<String, Object?> json, {required String labelKey}) {
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
      displayValue: null,
    );
  }

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}

class const QuotaAmount({
  required final String label,
  required final String currency,
  required final double? spentAmount,
  required final double? remainingAmount,
  required final double? limitAmount,
  required final DateTime? resetsAt,
  required final String? resetDescription,
}) {
  factory fromJson(Map<String, Object?> json) {
    double? number(Object? value) => switch (value) {
      final num n => n.toDouble(),
      final String raw => double.tryParse(raw),
      _ => null,
    };
    final reset = json['resetsAt'] as int?;
    return QuotaAmount(
      label: json['label'] as String? ?? 'Spend',
      currency: json['currency'] as String? ?? 'USD',
      spentAmount: number(json['spentAmount']),
      remainingAmount: number(json['remainingAmount']),
      limitAmount: number(json['limitAmount']),
      resetsAt: reset == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reset, isUtc: true),
      resetDescription: json['resetDescription'] as String?,
    );
  }
}
