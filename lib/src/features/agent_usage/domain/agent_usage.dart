enum AgentUsageProvider { claude, codex, grok }

enum AgentUsageCostSource { providerReported, modelPriced, unpriced }

enum AgentUsageSourceStatus { ok, missing, partial, failed }

enum AgentUsagePricingStatus { fresh, cached, unavailable }

class const AgentUsageTokenTotals({
  required final int uncachedInputTokens,
  required final int cachedInputTokens,
  required final int cacheCreationTokens,
  required final int outputTokens,
  required final int reasoningTokens,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentUsageTokenTotals(
      uncachedInputTokens: _nonNegativeInt(json['uncachedInputTokens']),
      cachedInputTokens: _nonNegativeInt(json['cachedInputTokens']),
      cacheCreationTokens: _nonNegativeInt(json['cacheCreationTokens']),
      outputTokens: _nonNegativeInt(json['outputTokens']),
      reasoningTokens: _nonNegativeInt(json['reasoningTokens']),
    );
  }

  static const zero = AgentUsageTokenTotals(
    uncachedInputTokens: 0,
    cachedInputTokens: 0,
    cacheCreationTokens: 0,
    outputTokens: 0,
    reasoningTokens: 0,
  );

  int get totalTokens =>
      uncachedInputTokens +
      cachedInputTokens +
      cacheCreationTokens +
      outputTokens;

  int get totalInputTokens =>
      uncachedInputTokens + cachedInputTokens + cacheCreationTokens;

  AgentUsageTokenTotals operator +(AgentUsageTokenTotals other) {
    return AgentUsageTokenTotals(
      uncachedInputTokens: uncachedInputTokens + other.uncachedInputTokens,
      cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
      cacheCreationTokens: cacheCreationTokens + other.cacheCreationTokens,
      outputTokens: outputTokens + other.outputTokens,
      reasoningTokens: reasoningTokens + other.reasoningTokens,
    );
  }
}

class const AgentUsageBucket({
  required final String day,
  required final AgentUsageProvider provider,
  required final String accountId,
  required final String displayName,
  required final String model,
  required final AgentUsageTokenTotals totals,
  required final double costUsd,
  required final double cacheSavingsUsd,
  required final AgentUsageCostSource costSource,
  required final int records,
  required final int unpricedRecords,
  required final int sessions,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentUsageBucket(
      day: json['day'] as String? ?? '',
      provider: _enumByName(
        AgentUsageProvider.values,
        json['provider'],
        .codex,
      ),
      accountId: json['accountId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      model: json['model'] as String? ?? 'Unknown',
      totals: .fromJson(_object(json['totals'])),
      costUsd: _nonNegativeDouble(json['costUsd']),
      cacheSavingsUsd: _nonNegativeDouble(json['cacheSavingsUsd']),
      costSource: _enumByName(
        AgentUsageCostSource.values,
        json['costSource'],
        .unpriced,
      ),
      records: _nonNegativeInt(json['records']),
      unpricedRecords: _nonNegativeInt(json['unpricedRecords']),
      sessions: _nonNegativeInt(json['sessions']),
    );
  }
}

class const AgentUsageSource({
  required final AgentUsageProvider provider,
  required final String accountId,
  required final String displayName,
  required final AgentUsageSourceStatus status,
  required final int scannedFiles,
  required final int skippedFiles,
  required final int distinctSessions,
  required final String? message,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentUsageSource(
      provider: _enumByName(
        AgentUsageProvider.values,
        json['provider'],
        .codex,
      ),
      accountId: json['accountId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      status: _enumByName(
        AgentUsageSourceStatus.values,
        json['status'],
        .failed,
      ),
      scannedFiles: _nonNegativeInt(json['scannedFiles']),
      skippedFiles: _nonNegativeInt(json['skippedFiles']),
      distinctSessions: _nonNegativeInt(json['distinctSessions']),
      message: json['message'] as String?,
    );
  }
}

class const AgentUsagePricing({
  required final AgentUsagePricingStatus status,
  required final String source,
  required final int knownModels,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentUsagePricing(
      status: _enumByName(
        AgentUsagePricingStatus.values,
        json['status'],
        .unavailable,
      ),
      source: json['source'] as String? ?? '',
      knownModels: _nonNegativeInt(json['knownModels']),
    );
  }
}

class const AgentUsageSnapshot({
  required final DateTime readAt,
  required final String sinceDay,
  required final String untilDay,
  required final List<AgentUsageBucket> buckets,
  required final List<AgentUsageSource> sources,
  required final AgentUsagePricing pricing,
  required final int scanDurationMs,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentUsageSnapshot(
      readAt: .fromMillisecondsSinceEpoch(
        _nonNegativeInt(json['readAt']),
        isUtc: true,
      ),
      sinceDay: json['sinceDay'] as String? ?? '',
      untilDay: json['untilDay'] as String? ?? '',
      buckets: _objects(json['buckets'])
          .map(AgentUsageBucket.fromJson)
          .toList(growable: false),
      sources: _objects(json['sources'])
          .map(AgentUsageSource.fromJson)
          .toList(growable: false),
      pricing: .fromJson(_object(json['pricing'])),
      scanDurationMs: _nonNegativeInt(json['scanDurationMs']),
    );
  }

  AgentUsageTokenTotals get totals =>
      buckets.fold(.zero, (sum, bucket) => sum + bucket.totals);

  double get costUsd => buckets.fold(0, (sum, bucket) => sum + bucket.costUsd);

  double get cacheSavingsUsd =>
      buckets.fold(0, (sum, bucket) => sum + bucket.cacheSavingsUsd);

  int get sessions =>
      sources.fold(0, (sum, source) => sum + source.distinctSessions);

  int get records => buckets.fold(0, (sum, bucket) => sum + bucket.records);

  List<AgentUsageBreakdown> get accounts {
    final values = <String, _MutableBreakdown>{};
    for (final bucket in buckets) {
      final key = '${bucket.provider.name}:${bucket.accountId}';
      values
          .putIfAbsent(
            key,
            () => _MutableBreakdown(
              provider: bucket.provider,
              label: _usageAccountLabel(bucket),
            ),
          )
          .add(bucket);
    }
    for (final source in sources) {
      final key = '${source.provider.name}:${source.accountId}';
      values[key]?.sessions = source.distinctSessions;
    }
    return _sortedBreakdowns(values);
  }

  List<AgentUsageBreakdown> get providers {
    final values = <String, _MutableBreakdown>{};
    for (final bucket in buckets) {
      final key = bucket.provider.name;
      values
          .putIfAbsent(
            key,
            () => _MutableBreakdown(
              provider: bucket.provider,
              label: switch (bucket.provider) {
                AgentUsageProvider.claude => 'Claude Code',
                AgentUsageProvider.codex => 'Codex',
                AgentUsageProvider.grok => 'Grok Build',
              },
            ),
          )
          .add(bucket);
    }
    final sourceSessions = <String, int>{};
    for (final source in sources) {
      sourceSessions.update(
        source.provider.name,
        (sessions) => sessions + source.distinctSessions,
        ifAbsent: () => source.distinctSessions,
      );
    }
    for (final entry in sourceSessions.entries) {
      values[entry.key]?.sessions = entry.value;
    }
    return _sortedBreakdowns(values);
  }

  List<AgentUsageBreakdown> get models {
    final values = <String, _MutableBreakdown>{};
    for (final bucket in buckets) {
      final key = '${bucket.provider.name}:${bucket.model}';
      values
          .putIfAbsent(
            key,
            () => _MutableBreakdown(
              provider: bucket.provider,
              label: bucket.model,
            ),
          )
          .add(bucket);
    }
    return _sortedBreakdowns(values);
  }

  List<AgentUsageDay> get days {
    final values = <String, AgentUsageDay>{};
    for (final bucket in buckets) {
      final current = values[bucket.day] ?? AgentUsageDay.empty(bucket.day);
      values[bucket.day] = current.add(bucket);
    }
    final first = DateTime.tryParse(sinceDay);
    final last = DateTime.tryParse(untilDay);
    if (first == null || last == null || first.isAfter(last)) {
      final sorted = values.values.toList()
        ..sort((a, b) => a.day.compareTo(b.day));
      return sorted;
    }
    return <AgentUsageDay>[
      for (
        var date = first;
        !date.isAfter(last);
        date = date.add(const Duration(days: 1))
      )
        values[_usageDay(date)] ?? AgentUsageDay.empty(_usageDay(date)),
    ];
  }
}

String _usageAccountLabel(AgentUsageBucket bucket) {
  return switch ((bucket.provider, bucket.accountId)) {
    (AgentUsageProvider.claude, 'default') => 'Claude Code Default',
    (AgentUsageProvider.codex, 'default') => 'Codex',
    (AgentUsageProvider.grok, 'default') => 'Grok Build',
    _ => bucket.displayName,
  };
}

class const AgentUsageBreakdown({
  required final AgentUsageProvider provider,
  required final String label,
  required final int tokens,
  required final double costUsd,
  required final int records,
  required final int sessions,
});

class const AgentUsageDay({
  required final String day,
  required final int claudeTokens,
  required final int codexTokens,
  final int grokTokens = 0,
  required final double costUsd,
}) {
  factory empty(String day) =>
      AgentUsageDay(day: day, claudeTokens: 0, codexTokens: 0, costUsd: 0);

  int get tokens => claudeTokens + codexTokens + grokTokens;

  AgentUsageDay add(AgentUsageBucket bucket) {
    return AgentUsageDay(
      day: day,
      claudeTokens:
          claudeTokens +
          (bucket.provider == AgentUsageProvider.claude
              ? bucket.totals.totalTokens
              : 0),
      codexTokens:
          codexTokens +
          (bucket.provider == AgentUsageProvider.codex
              ? bucket.totals.totalTokens
              : 0),
      grokTokens:
          grokTokens +
          (bucket.provider == AgentUsageProvider.grok
              ? bucket.totals.totalTokens
              : 0),
      costUsd: costUsd + bucket.costUsd,
    );
  }
}

class _MutableBreakdown({
  required final AgentUsageProvider provider,
  required final String label,
}) {
  int tokens = 0;
  double costUsd = 0;
  int records = 0;
  int sessions = 0;

  void add(AgentUsageBucket bucket) {
    tokens += bucket.totals.totalTokens;
    costUsd += bucket.costUsd;
    records += bucket.records;
    sessions += bucket.sessions;
  }

  AgentUsageBreakdown freeze() => AgentUsageBreakdown(
    provider: provider,
    label: label,
    tokens: tokens,
    costUsd: costUsd,
    records: records,
    sessions: sessions,
  );
}

List<AgentUsageBreakdown> _sortedBreakdowns(
  Map<String, _MutableBreakdown> values,
) {
  final result = values.values.map((value) => value.freeze()).toList();
  result.sort((left, right) => right.tokens.compareTo(left.tokens));
  return result;
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

int _nonNegativeInt(Object? value) => switch (value) {
  final int number when number > 0 => number,
  final num number when number > 0 => number.toInt(),
  _ => 0,
};

double _nonNegativeDouble(Object? value) => switch (value) {
  final num number when number.isFinite && number > 0 => number.toDouble(),
  _ => 0,
};

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

List<Map<String, Object?>> _objects(Object? value) => <Map<String, Object?>>[
  if (value is List)
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
];

String _usageDay(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
