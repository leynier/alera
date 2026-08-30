enum AgentUsageProvider { claude, codex, grok }

enum AgentUsageCostSource { providerReported, modelPriced, unpriced }

enum AgentUsageSourceStatus { ok, missing, partial, failed }

enum AgentUsagePricingStatus { fresh, cached, unavailable }

class AgentUsageTokenTotals {
  const AgentUsageTokenTotals({
    required this.uncachedInputTokens,
    required this.cachedInputTokens,
    required this.cacheCreationTokens,
    required this.outputTokens,
    required this.reasoningTokens,
  });

  factory AgentUsageTokenTotals.fromJson(Map<String, Object?> json) {
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

  final int uncachedInputTokens;
  final int cachedInputTokens;
  final int cacheCreationTokens;
  final int outputTokens;
  final int reasoningTokens;

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

class AgentUsageBucket {
  const AgentUsageBucket({
    required this.day,
    required this.provider,
    required this.accountId,
    required this.displayName,
    required this.model,
    required this.totals,
    required this.costUsd,
    required this.cacheSavingsUsd,
    required this.costSource,
    required this.records,
    required this.unpricedRecords,
    required this.sessions,
  });

  factory AgentUsageBucket.fromJson(Map<String, Object?> json) {
    return AgentUsageBucket(
      day: json['day'] as String? ?? '',
      provider: _enumByName(
        AgentUsageProvider.values,
        json['provider'],
        AgentUsageProvider.codex,
      ),
      accountId: json['accountId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      model: json['model'] as String? ?? 'Unknown',
      totals: AgentUsageTokenTotals.fromJson(_object(json['totals'])),
      costUsd: _nonNegativeDouble(json['costUsd']),
      cacheSavingsUsd: _nonNegativeDouble(json['cacheSavingsUsd']),
      costSource: _enumByName(
        AgentUsageCostSource.values,
        json['costSource'],
        AgentUsageCostSource.unpriced,
      ),
      records: _nonNegativeInt(json['records']),
      unpricedRecords: _nonNegativeInt(json['unpricedRecords']),
      sessions: _nonNegativeInt(json['sessions']),
    );
  }

  final String day;
  final AgentUsageProvider provider;
  final String accountId;
  final String displayName;
  final String model;
  final AgentUsageTokenTotals totals;
  final double costUsd;
  final double cacheSavingsUsd;
  final AgentUsageCostSource costSource;
  final int records;
  final int unpricedRecords;
  final int sessions;
}

class AgentUsageSource {
  const AgentUsageSource({
    required this.provider,
    required this.accountId,
    required this.displayName,
    required this.status,
    required this.scannedFiles,
    required this.skippedFiles,
    required this.distinctSessions,
    required this.message,
  });

  factory AgentUsageSource.fromJson(Map<String, Object?> json) {
    return AgentUsageSource(
      provider: _enumByName(
        AgentUsageProvider.values,
        json['provider'],
        AgentUsageProvider.codex,
      ),
      accountId: json['accountId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      status: _enumByName(
        AgentUsageSourceStatus.values,
        json['status'],
        AgentUsageSourceStatus.failed,
      ),
      scannedFiles: _nonNegativeInt(json['scannedFiles']),
      skippedFiles: _nonNegativeInt(json['skippedFiles']),
      distinctSessions: _nonNegativeInt(json['distinctSessions']),
      message: json['message'] as String?,
    );
  }

  final AgentUsageProvider provider;
  final String accountId;
  final String displayName;
  final AgentUsageSourceStatus status;
  final int scannedFiles;
  final int skippedFiles;
  final int distinctSessions;
  final String? message;
}

class AgentUsagePricing {
  const AgentUsagePricing({
    required this.status,
    required this.source,
    required this.knownModels,
  });

  factory AgentUsagePricing.fromJson(Map<String, Object?> json) {
    return AgentUsagePricing(
      status: _enumByName(
        AgentUsagePricingStatus.values,
        json['status'],
        AgentUsagePricingStatus.unavailable,
      ),
      source: json['source'] as String? ?? '',
      knownModels: _nonNegativeInt(json['knownModels']),
    );
  }

  final AgentUsagePricingStatus status;
  final String source;
  final int knownModels;
}

class AgentUsageSnapshot {
  const AgentUsageSnapshot({
    required this.readAt,
    required this.sinceDay,
    required this.untilDay,
    required this.buckets,
    required this.sources,
    required this.pricing,
    required this.scanDurationMs,
  });

  factory AgentUsageSnapshot.fromJson(Map<String, Object?> json) {
    return AgentUsageSnapshot(
      readAt: DateTime.fromMillisecondsSinceEpoch(
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
      pricing: AgentUsagePricing.fromJson(_object(json['pricing'])),
      scanDurationMs: _nonNegativeInt(json['scanDurationMs']),
    );
  }

  final DateTime readAt;
  final String sinceDay;
  final String untilDay;
  final List<AgentUsageBucket> buckets;
  final List<AgentUsageSource> sources;
  final AgentUsagePricing pricing;
  final int scanDurationMs;

  AgentUsageTokenTotals get totals => buckets.fold(
    AgentUsageTokenTotals.zero,
    (sum, bucket) => sum + bucket.totals,
  );

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

class AgentUsageBreakdown {
  const AgentUsageBreakdown({
    required this.provider,
    required this.label,
    required this.tokens,
    required this.costUsd,
    required this.records,
    required this.sessions,
  });

  final AgentUsageProvider provider;
  final String label;
  final int tokens;
  final double costUsd;
  final int records;
  final int sessions;
}

class AgentUsageDay {
  const AgentUsageDay({
    required this.day,
    required this.claudeTokens,
    required this.codexTokens,
    this.grokTokens = 0,
    required this.costUsd,
  });

  factory AgentUsageDay.empty(String day) =>
      AgentUsageDay(day: day, claudeTokens: 0, codexTokens: 0, costUsd: 0);

  final String day;
  final int claudeTokens;
  final int codexTokens;
  final int grokTokens;
  final double costUsd;

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

class _MutableBreakdown {
  _MutableBreakdown({required this.provider, required this.label});

  final AgentUsageProvider provider;
  final String label;
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
