import 'package:alera/src/features/settings/domain/alera_settings.dart';

enum AgentQuotaStatus { ok, stale, error, unavailable }

enum CodexResetConsumeStatus { consumed, rejected }

enum CodexResetConsumeOutcome {
  reset,
  nothingToReset,
  noCredit,
  alreadyRedeemed,
}

class CodexResetCredits {
  const CodexResetCredits({
    required this.availableCount,
    required this.totalEarnedCount,
    required this.nextExpiresAt,
    required this.offerRevision,
    required this.canConsume,
  });

  factory CodexResetCredits.fromJson(Map<String, Object?> json) {
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

  final int availableCount;
  final int? totalEarnedCount;
  final DateTime? nextExpiresAt;
  final String offerRevision;
  final bool canConsume;
}

class AgentQuotaWindow {
  const AgentQuotaWindow({
    required this.label,
    required this.usedPercent,
    required this.windowMinutes,
    required this.resetsAt,
    required this.resetDescription,
    this.spentAmount,
    this.remainingAmount,
    this.limitAmount,
    this.currency,
  });

  factory AgentQuotaWindow.fromJson(Map<String, Object?> json) {
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

  final String label;
  final double usedPercent;
  final int? windowMinutes;
  final DateTime? resetsAt;
  final String? resetDescription;
  final double? spentAmount;
  final double? remainingAmount;
  final double? limitAmount;
  final String? currency;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
}

class AgentQuotaBucket {
  const AgentQuotaBucket({
    required this.name,
    required this.usedPercent,
    required this.windowMinutes,
    required this.resetsAt,
    required this.resetDescription,
    this.spentAmount,
    this.remainingAmount,
    this.limitAmount,
    this.currency,
  });

  factory AgentQuotaBucket.fromJson(Map<String, Object?> json) {
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

  final String name;
  final double usedPercent;
  final int? windowMinutes;
  final DateTime? resetsAt;
  final String? resetDescription;
  final double? spentAmount;
  final double? remainingAmount;
  final double? limitAmount;
  final String? currency;

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
    this.rateLimitResetCredits,
    this.dataQuality,
    this.scope,
    this.amounts = const <AgentQuotaAmount>[],
  });

  factory AgentQuotaSnapshot.fromJson(Map<String, Object?> json) {
    return AgentQuotaSnapshot._fromJson(
      json,
      AgentQuotaProviderId.values.firstWhere(
        (provider) => provider.name == json['provider'],
      ),
    );
  }

  factory AgentQuotaSnapshot._fromJson(
    Map<String, Object?> json,
    AgentQuotaProviderId provider,
  ) {
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
      windows: _objectList(
        json['windows'],
      ).map(AgentQuotaWindow.fromJson).toList(growable: false),
      buckets: _objectList(
        json['buckets'],
      ).map(AgentQuotaBucket.fromJson).toList(growable: false),
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

  final AgentQuotaProviderId provider;
  final String accountId;
  final String displayName;
  final AgentQuotaStatus status;
  final DateTime updatedAt;
  final String? error;
  final List<AgentQuotaWindow> windows;
  final List<AgentQuotaBucket> buckets;
  final CodexResetCredits? rateLimitResetCredits;
  final String? dataQuality;
  final String? scope;
  final List<AgentQuotaAmount> amounts;

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
      status: AgentQuotaStatus.stale,
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

class AgentQuotaAmount {
  const AgentQuotaAmount({
    required this.label,
    required this.currency,
    required this.spentAmount,
    required this.remainingAmount,
    required this.limitAmount,
    required this.resetsAt,
    required this.resetDescription,
  });

  factory AgentQuotaAmount.fromJson(Map<String, Object?> json) {
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

  final String label;
  final String currency;
  final double? spentAmount;
  final double? remainingAmount;
  final double? limitAmount;
  final DateTime? resetsAt;
  final String? resetDescription;
}

class CodexResetConsumeResult {
  const CodexResetConsumeResult({
    required this.status,
    required this.outcome,
    required this.reason,
    required this.snapshot,
  });

  factory CodexResetConsumeResult.fromJson(Map<String, Object?> json) {
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
      snapshot: AgentQuotaSnapshot.fromJson(
        Map<String, Object?>.from(snapshot),
      ),
    );
  }

  final CodexResetConsumeStatus status;
  final CodexResetConsumeOutcome? outcome;
  final String? reason;
  final AgentQuotaSnapshot snapshot;
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
