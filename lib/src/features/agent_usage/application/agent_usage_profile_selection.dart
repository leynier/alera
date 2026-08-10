import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';

extension AgentUsageProfileSelection on AgentUsageSnapshot {
  AgentUsageSnapshot withClaudeProfileSelection({
    required bool defaultEnabled,
    required Map<String, String> profileLabels,
  }) {
    bool includes(AgentUsageProvider provider, String accountId) {
      if (provider != AgentUsageProvider.claude) return true;
      return accountId == 'default'
          ? defaultEnabled
          : profileLabels.containsKey(accountId);
    }

    String displayName(
      AgentUsageProvider provider,
      String current,
      String accountId,
    ) {
      if (provider != AgentUsageProvider.claude || accountId == 'default') {
        return current;
      }
      return profileLabels[accountId] ?? current;
    }

    return AgentUsageSnapshot(
      readAt: readAt,
      sinceDay: sinceDay,
      untilDay: untilDay,
      buckets: <AgentUsageBucket>[
        for (final bucket in buckets)
          if (includes(bucket.provider, bucket.accountId))
            AgentUsageBucket(
              day: bucket.day,
              provider: bucket.provider,
              accountId: bucket.accountId,
              displayName: displayName(
                bucket.provider,
                bucket.displayName,
                bucket.accountId,
              ),
              model: bucket.model,
              totals: bucket.totals,
              costUsd: bucket.costUsd,
              cacheSavingsUsd: bucket.cacheSavingsUsd,
              costSource: bucket.costSource,
              records: bucket.records,
              unpricedRecords: bucket.unpricedRecords,
              sessions: bucket.sessions,
            ),
      ],
      sources: <AgentUsageSource>[
        for (final source in sources)
          if (includes(source.provider, source.accountId))
            AgentUsageSource(
              provider: source.provider,
              accountId: source.accountId,
              displayName: displayName(
                source.provider,
                source.displayName,
                source.accountId,
              ),
              status: source.status,
              scannedFiles: source.scannedFiles,
              skippedFiles: source.skippedFiles,
              distinctSessions: source.distinctSessions,
              message: source.message,
            ),
      ],
      pricing: pricing,
      scanDurationMs: scanDurationMs,
    );
  }
}
