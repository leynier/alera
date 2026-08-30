part of 'agent_usage_dialog.dart';

enum _UsageBreakdownMode { profile, grouped, model }

class const _AgentUsageContent({
  required final AgentUsageSnapshot snapshot,
  required final bool showGroupedBreakdown,
}) extends StatefulWidget {
  @override
  State<_AgentUsageContent> createState() => _AgentUsageContentState();
}

class _AgentUsageContentState extends State<_AgentUsageContent> {
  _UsageBreakdownMode _mode = .profile;

  @override
  void didUpdateWidget(covariant _AgentUsageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showGroupedBreakdown && _mode == _UsageBreakdownMode.grouped) {
      _mode = _UsageBreakdownMode.profile;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final totals = snapshot.totals;
    final cachedShare = totals.totalInputTokens == 0
        ? 0.0
        : totals.cachedInputTokens / totals.totalInputTokens;
    final breakdown = switch (_mode) {
      _UsageBreakdownMode.profile => snapshot.accounts,
      _UsageBreakdownMode.grouped => snapshot.providers,
      _UsageBreakdownMode.model => snapshot.models,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AleraTokens.space20),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _UsageCoverageNotice(snapshot: snapshot),
          if (_hasCoverageNotice(snapshot))
            const SizedBox(height: AleraTokens.space12),
          _UsageMetrics(
            metrics: <Widget>[
              _UsageMetric(
                key: const ValueKey<String>('usage-metric-processed-tokens'),
                label: 'Processed Tokens',
                value: _formatUsageTokens(totals.totalTokens),
                detail: '${snapshot.records} assistant responses',
              ),
              _UsageMetric(
                key: const ValueKey<String>('usage-metric-api-cost'),
                label: 'API-Equivalent Cost',
                value: _formatUsageUsd(snapshot.costUsd),
                detail: _usagePricingDetail(snapshot),
              ),
              _UsageMetric(
                key: const ValueKey<String>('usage-metric-sessions'),
                label: 'Sessions',
                value: _formatUsageCount(snapshot.sessions),
                detail: '${snapshot.sources.length} transcript sources',
              ),
              _UsageMetric(
                key: const ValueKey<String>('usage-metric-cached-input'),
                label: 'Cached Input',
                value: _formatUsageTokens(totals.cachedInputTokens),
                detail: _formatUsagePercent(cachedShare),
              ),
              _UsageMetric(
                key: const ValueKey<String>('usage-metric-cache-savings'),
                label: 'Cache Savings',
                value: _formatUsageUsd(snapshot.cacheSavingsUsd),
                detail: 'Compared with full input rates',
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space20),
          Text('Daily Activity', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Tokens read from Claude Code, Codex, and Grok Build transcripts on this host.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(height: AleraTokens.space12),
          AgentUsageDailyChart(days: snapshot.days),
          const SizedBox(height: AleraTokens.space20),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Breakdown',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              AleraSegmentedButton<_UsageBreakdownMode>(
                dense: true,
                segments: <ButtonSegment<_UsageBreakdownMode>>[
                  const ButtonSegment<_UsageBreakdownMode>(
                    value: .profile,
                    label: Text('Profiles'),
                  ),
                  if (widget.showGroupedBreakdown)
                    const ButtonSegment<_UsageBreakdownMode>(
                      value: .grouped,
                      label: Text('Grouped'),
                    ),
                  const ButtonSegment<_UsageBreakdownMode>(
                    value: .model,
                    label: Text('Models'),
                  ),
                ],
                selected: _mode,
                onSelectionChanged: (value) => setState(() => _mode = value),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
          _UsageBreakdownTable(values: breakdown),
          const SizedBox(height: AleraTokens.space16),
          _UsageSourceSummary(snapshot: snapshot),
        ],
      ),
    );
  }
}

class const _UsageBreakdownTable({
  required final List<AgentUsageBreakdown> values,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const AleraEmptyState(
        title: 'No Activity',
        message: 'No Claude Code, Codex, or Grok Build usage was found in this range.',
      );
    }
    return AleraPanel(
      children: <Widget>[
        const _UsageTableHeader(),
        for (final value in values) _UsageBreakdownRow(value: value),
      ],
    );
  }
}

class const _UsageTableHeader() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('Name')),
          SizedBox(
            width: AleraTokens.usageTokensColumnWidth,
            child: Text('Tokens', textAlign: .end),
          ),
          SizedBox(
            width: AleraTokens.usageCostColumnWidth,
            child: Text('Cost', textAlign: .end),
          ),
          SizedBox(
            width: AleraTokens.usageSessionsColumnWidth,
            child: Text('Responses', textAlign: .end),
          ),
        ],
      ),
    );
  }
}

class const _UsageBreakdownRow({required final AgentUsageBreakdown value})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final quotaProvider = switch (value.provider) {
      AgentUsageProvider.claude => AgentQuotaProviderId.claude,
      AgentUsageProvider.codex => AgentQuotaProviderId.codex,
      AgentUsageProvider.grok => AgentQuotaProviderId.grok,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          AgentQuotaProviderIcon(
            provider: quotaProvider,
            size: AleraTokens.iconMd,
            showTooltip: false,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(child: Text(value.label, overflow: .ellipsis)),
          SizedBox(
            width: AleraTokens.usageTokensColumnWidth,
            child: Text(
              _formatUsageTokens(value.tokens),
              textAlign: .end,
              style: AleraTokens.monoCompactStyle,
            ),
          ),
          SizedBox(
            width: AleraTokens.usageCostColumnWidth,
            child: Text(
              _formatUsageUsd(value.costUsd),
              textAlign: .end,
              style: AleraTokens.monoCompactStyle,
            ),
          ),
          SizedBox(
            width: AleraTokens.usageSessionsColumnWidth,
            child: Text(
              _formatUsageCount(value.records),
              textAlign: .end,
              style: AleraTokens.monoCompactStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class const _UsageSourceSummary({required final AgentUsageSnapshot snapshot})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Scanned ${snapshot.sources.fold(0, (sum, source) => sum + source.scannedFiles)} files in ${snapshot.scanDurationMs} ms. Transcript content stays on this host.',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundFaint),
    );
  }
}

class const _UsageCoverageNotice({required final AgentUsageSnapshot snapshot})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!_hasCoverageNotice(snapshot)) return const SizedBox.shrink();
    final sourceIssues = snapshot.sources.where(
      (source) =>
          source.status == AgentUsageSourceStatus.partial ||
          source.status == AgentUsageSourceStatus.failed,
    );
    final messages = <String>[
      for (final source in sourceIssues)
        '${_usageProviderLabel(source.provider)} ${source.displayName} is partial.',
      if (snapshot.pricing.status == AgentUsagePricingStatus.unavailable) 'Some model costs may be unavailable because pricing could not be loaded.',
    ];
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Text(
        messages.join(' '),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}

bool _hasCoverageNotice(AgentUsageSnapshot snapshot) {
  return snapshot.pricing.status == AgentUsagePricingStatus.unavailable ||
      snapshot.sources.any(
        (source) =>
            source.status == AgentUsageSourceStatus.partial ||
            source.status == AgentUsageSourceStatus.failed,
      );
}
