part of 'agent_quota_status_bar.dart';

const double _quotaHoverCardWidth = 360;
const double _quotaHoverCardMaxHeight = 480;

class _AgentQuotaHoverCard extends StatelessWidget {
  const _AgentQuotaHoverCard({
    required this.snapshots,
    this.profileLabels = const <String, String>{},
    this.emptyMessage = 'Quota Data Unavailable',
  });

  final List<AgentQuotaSnapshot> snapshots;
  final Map<String, String> profileLabels;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _quotaHoverCardWidth,
      constraints: const BoxConstraints(maxHeight: _quotaHoverCardMaxHeight),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AleraTokens.shadowSoft,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (snapshots.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: Text(
                    _normalizeQuotaText(emptyMessage),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              for (final (index, snapshot) in snapshots.indexed) ...<Widget>[
                if (index > 0)
                  const Divider(height: 1, color: AleraTokens.border),
                _AgentQuotaHoverSection(
                  snapshot: snapshot,
                  profileLabel: profileLabels[snapshot.key],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentQuotaHoverSection extends StatelessWidget {
  const _AgentQuotaHoverSection({
    required this.snapshot,
    required this.profileLabel,
  });

  final AgentQuotaSnapshot snapshot;
  final String? profileLabel;

  @override
  Widget build(BuildContext context) {
    final entries = _quotaHoverEntries(snapshot);
    final statusColor = _quotaColor(snapshot.status, snapshot.remainingPercent);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AgentQuotaProviderIcon(
                provider: snapshot.provider,
                size: 18,
                showTooltip: false,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      snapshot.provider.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (profileLabel != null)
                      Text(
                        profileLabel!,
                        style: AleraTokens.monoStyle.copyWith(
                          fontSize: 10,
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                  ],
                ),
              ),
              AleraBadge(
                label: _quotaStatusLabel(snapshot.status),
                color: statusColor.withAlpha(28),
                foregroundColor: statusColor,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space12),
          if (entries.isEmpty)
            _QuotaHoverEmptyState(snapshot: snapshot)
          else
            for (final (index, entry) in entries.indexed) ...<Widget>[
              if (index > 0) const SizedBox(height: AleraTokens.space12),
              _QuotaHoverReading(entry: entry, status: snapshot.status),
            ],
        ],
      ),
    );
  }
}

class _QuotaHoverReading extends StatelessWidget {
  const _QuotaHoverReading({required this.entry, required this.status});

  final _QuotaHoverEntry entry;
  final AgentQuotaStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _quotaColor(status, entry.remainingPercent);
    final label = _quotaHoverLabel(entry.provider, entry.label);
    final reset =
        _resetText(entry.resetsAt, entry.resetDescription) ??
        'Reset Time Unavailable';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space12),
            Text(
              '${entry.remainingPercent.round()}% Left',
              style: AleraTokens.monoStyle.copyWith(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space6),
        LinearProgressIndicator(
          value: entry.remainingPercent / 100,
          minHeight: AleraTokens.space4,
          color: color,
          backgroundColor: AleraTokens.surfaceVariant,
          borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
          semanticsLabel: '$label Remaining',
          semanticsValue: '${entry.remainingPercent.round()}%',
        ),
        const SizedBox(height: AleraTokens.space6),
        Text(
          reset,
          style: AleraTokens.monoStyle.copyWith(
            fontSize: 9,
            color: AleraTokens.foregroundFaint,
          ),
        ),
      ],
    );
  }
}

class _QuotaHoverEmptyState extends StatelessWidget {
  const _QuotaHoverEmptyState({required this.snapshot});

  final AgentQuotaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Text(
      snapshot.error == null
          ? 'Quota Data Unavailable'
          : _normalizeQuotaText(snapshot.error!),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}

class _QuotaHoverEntry {
  const _QuotaHoverEntry({
    required this.provider,
    required this.label,
    required this.remainingPercent,
    required this.resetsAt,
    required this.resetDescription,
  });

  final AgentQuotaProviderId provider;
  final String label;
  final double remainingPercent;
  final DateTime? resetsAt;
  final String? resetDescription;
}

List<_QuotaHoverEntry> _quotaHoverEntries(AgentQuotaSnapshot snapshot) {
  return <_QuotaHoverEntry>[
    for (final window in snapshot.windows)
      _QuotaHoverEntry(
        provider: snapshot.provider,
        label: window.label,
        remainingPercent: window.remainingPercent,
        resetsAt: window.resetsAt,
        resetDescription: window.resetDescription,
      ),
    for (final bucket in snapshot.buckets)
      _QuotaHoverEntry(
        provider: snapshot.provider,
        label: bucket.name,
        remainingPercent: bucket.remainingPercent,
        resetsAt: bucket.resetsAt,
        resetDescription: bucket.resetDescription,
      ),
  ]..sort(
    (left, right) => _readingOrder(
      snapshot.provider,
      left.label,
    ).compareTo(_readingOrder(snapshot.provider, right.label)),
  );
}

String _quotaHoverLabel(AgentQuotaProviderId provider, String value) {
  final normalized = _normalizeQuotaText(value);
  if (provider != AgentQuotaProviderId.minimax || normalized.isEmpty) {
    return normalized;
  }
  return normalized[0].toUpperCase() + normalized.substring(1);
}

String _quotaStatusLabel(AgentQuotaStatus status) {
  return switch (status) {
    AgentQuotaStatus.ok => 'Live',
    AgentQuotaStatus.stale => 'Stale',
    AgentQuotaStatus.error => 'Error',
    AgentQuotaStatus.unavailable => 'Unavailable',
  };
}
