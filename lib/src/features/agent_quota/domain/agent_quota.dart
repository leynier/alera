import 'package:alera/src/features/settings/domain/alera_settings.dart';

enum AgentQuotaStatus { ok, stale, error, unavailable }

enum CodexResetConsumeStatus { consumed, rejected }

enum CodexResetConsumeOutcome {
  reset,
  nothingToReset,
  noCredit,
  alreadyRedeemed,
}

class const CodexResetCredits({
  required final int availableCount,
  required final int? totalEarnedCount,
  required final DateTime? nextExpiresAt,
  required final String offerRevision,
  required final bool canConsume,
}) {
  factory fromJson(Map<String, Object?> json) {
    return CodexResetCredits(
      availableCount: switch (json['availableCount']) {
        final int count when count > 0 => count,
        _ => 0,
      },
      totalEarnedCount: json['totalEarnedCount'] as int?,
      nextExpiresAt: _dateFromMillis(json['nextExpiresAt']),
      offerRevision: json['offerRevision'] as String? ?? '',
      canConsume: json['canConsume'] == true,
    );
  }
}

class const AgentQuotaWindow({
  required final String label,
  required final double usedPercent,
  required final int? windowMinutes,
  required final DateTime? resetsAt,
  required final String? resetDescription,
  final double? spentAmount,
  final double? remainingAmount,
  final double? limitAmount,
  final String? currency,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentQuotaWindow(
      label: (json['label'] as String?) ?? 'Quota',
      usedPercent: _doubleValue(json['usedPercent']),
      windowMinutes: json['windowMinutes'] as int?,
      resetsAt: _dateFromMillis(json['resetsAt']),
      resetDescription: json['resetDescription'] as String?,
      spentAmount: _amountValue(json['spentAmount']),
      remainingAmount: _amountValue(json['remainingAmount']),
      limitAmount: _amountValue(json['limitAmount']),
      currency: json['currency'] as String?,
    );
  }

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}

class const AgentQuotaBucket({
  required final String name,
  required final double usedPercent,
  required final int? windowMinutes,
  required final DateTime? resetsAt,
  required final String? resetDescription,
  final double? spentAmount,
  final double? remainingAmount,
  final double? limitAmount,
  final String? currency,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentQuotaBucket(
      name: (json['name'] as String?) ?? 'Quota',
      usedPercent: _doubleValue(json['usedPercent']),
      windowMinutes: json['windowMinutes'] as int?,
      resetsAt: _dateFromMillis(json['resetsAt']),
      resetDescription: json['resetDescription'] as String?,
      spentAmount: _amountValue(json['spentAmount']),
      remainingAmount: _amountValue(json['remainingAmount']),
      limitAmount: _amountValue(json['limitAmount']),
      currency: json['currency'] as String?,
    );
  }

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}

class const AgentQuotaSnapshot({
  required final AgentQuotaProviderId provider,
  required final String accountId,
  required final String displayName,
  required final AgentQuotaStatus status,
  required final DateTime updatedAt,
  required final String? error,
  required final List<AgentQuotaWindow> windows,
  required final List<AgentQuotaBucket> buckets,
  final CodexResetCredits? rateLimitResetCredits,
  final String? dataQuality,
  final String? scope,
  final List<AgentQuotaAmount> amounts = const <AgentQuotaAmount>[],
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentQuotaSnapshot._fromJson(
      json,
      AgentQuotaProviderId.values.firstWhere(
        (provider) => provider.name == json['provider'],
      ),
    );
  }

  factory _fromJson(Map<String, Object?> json, AgentQuotaProviderId provider) {
    return AgentQuotaSnapshot(
      provider: provider,
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
      windows: _objectList(json['windows'])
          .map(AgentQuotaWindow.fromJson)
          .toList(growable: false),
      buckets: _objectList(json['buckets'])
          .map(AgentQuotaBucket.fromJson)
          .toList(growable: false),
      rateLimitResetCredits: switch (json['rateLimitResetCredits']) {
        final Map value => CodexResetCredits.fromJson(
          Map<String, Object?>.from(value),
        ),
        _ => null,
      },
      dataQuality: json['dataQuality'] as String?,
      scope: json['scope'] as String?,
      amounts: _objectList(json['amounts'])
          .map(AgentQuotaAmount.fromJson)
          .toList(growable: false),
    );
  }

  /// Same as [fromJson] but returns `null` if the payload's `provider` value
  /// is not a known [AgentQuotaProviderId] (e.g., a newer runtime version
  /// added a provider the client does not know yet). This lets callers drop
  /// the single unknown entry instead of failing the whole quota refresh.
  static AgentQuotaSnapshot? tryFromJson(Map<String, Object?> json) {
    AgentQuotaProviderId? provider;
    for (final candidate in AgentQuotaProviderId.values) {
      if (candidate.name == json['provider']) {
        provider = candidate;
        break;
      }
    }
    if (provider == null) return null;
    return AgentQuotaSnapshot._fromJson(json, provider);
  }

  String get key => '${provider.name}:$accountId';

  String get pinKey =>
      AgentQuotaHostSettings.quotaPinKey(provider, claudeAccountId: accountId);

  bool get hasUsage =>
      windows.isNotEmpty || buckets.isNotEmpty || amounts.isNotEmpty;

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
      status: .stale,
      updatedAt: updatedAt,
      error: freshError,
      windows: windows,
      buckets: buckets,
      rateLimitResetCredits: rateLimitResetCredits,
      dataQuality: dataQuality,
      scope: scope,
      amounts: amounts,
    );
  }
}

class const AgentQuotaAmount({
  required final String label,
  required final String currency,
  required final double? spentAmount,
  required final double? remainingAmount,
  required final double? limitAmount,
  required final DateTime? resetsAt,
  required final String? resetDescription,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentQuotaAmount(
      label: json['label'] as String? ?? 'Spend',
      currency: json['currency'] as String? ?? 'USD',
      spentAmount: _amountValue(json['spentAmount']),
      remainingAmount: _amountValue(json['remainingAmount']),
      limitAmount: _amountValue(json['limitAmount']),
      resetsAt: _dateFromMillis(json['resetsAt']),
      resetDescription: json['resetDescription'] as String?,
    );
  }
}

class const CodexResetConsumeResult({
  required final CodexResetConsumeStatus status,
  required final CodexResetConsumeOutcome? outcome,
  required final String? reason,
  required final AgentQuotaSnapshot snapshot,
}) {
  factory fromJson(Map<String, Object?> json) {
    final snapshot = json['snapshot'];
    if (snapshot is! Map) {
      throw const FormatException('Codex reset response missing snapshot.');
    }
    return CodexResetConsumeResult(
      status: CodexResetConsumeStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => CodexResetConsumeStatus.rejected,
      ),
      outcome: CodexResetConsumeOutcome.values
          .where((outcome) => outcome.name == json['outcome'])
          .firstOrNull,
      reason: json['reason'] as String?,
      snapshot: .fromJson(Map<String, Object?>.from(snapshot)),
    );
  }
}

class const AgentQuotaState({
  required final String hostId,
  required final List<AgentQuotaSnapshot> snapshots,
  required final Map<String, bool> environment,
  required final DateTime fetchedAt,
  final String? error,
}) {
  factory empty(String hostId) {
    return AgentQuotaState(
      hostId: hostId,
      snapshots: const <AgentQuotaSnapshot>[],
      environment: const <String, bool>{},
      fetchedAt: .fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
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

double? _amountValue(Object? value) {
  return switch (value) {
    final num number => number.toDouble(),
    final String raw => double.tryParse(raw),
    _ => null,
  };
}

DateTime? _dateFromMillis(Object? value) {
  if (value is! int) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}
