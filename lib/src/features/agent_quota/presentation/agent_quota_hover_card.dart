part of 'agent_quota_status_bar_content.dart';

const double _quotaHoverCardWidth = 360;
const double _quotaHoverCardMaxHeight = 480;

class const _AgentQuotaHoverCard({
  required final List<AgentQuotaSnapshot> snapshots,
  final Map<String, String> profileLabels = const <String, String>{},
  final String hostId = 'local',
  final AgentQuotaInlineActions actions = const AgentQuotaInlineActions(),
}) extends StatelessWidget {
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
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              if (snapshots.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: Text(
                    _normalizeQuotaText('Quota data unavailable'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
                ),
              for (final (index, snapshot) in snapshots.indexed) ...<Widget>[
                if (index > 0)
                  const Divider(height: 1, color: AleraTokens.border),
                _AgentQuotaHoverSection(
                  snapshot: snapshot,
                  profileLabel: profileLabels[snapshot.key],
                  hostId: hostId,
                  actions: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class const _AgentQuotaHoverSection({
  required final AgentQuotaSnapshot snapshot,
  required final String? profileLabel,
  required final String hostId,
  final AgentQuotaInlineActions actions = const AgentQuotaInlineActions(),
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final entries = _quotaHoverEntries(snapshot);
    final statusColor = _quotaColor(snapshot.status, snapshot.remainingPercent);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
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
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      snapshot.provider.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
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
                label: _quotaStatusLabel(snapshot),
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
          if (snapshot.provider == AgentQuotaProviderId.codex &&
              snapshot.rateLimitResetCredits != null)
            actions.buildCodexReset(hostId: hostId, snapshot: snapshot),
          if (_shouldOfferClaudeTui(snapshot)) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            actions.buildClaudeTui(hostId: hostId, snapshot: snapshot),
          ],
        ],
      ),
    );
  }
}

bool _shouldOfferClaudeTui(AgentQuotaSnapshot snapshot) {
  return snapshot.provider == AgentQuotaProviderId.claude &&
      snapshot.status != AgentQuotaStatus.ok;
}

class const _QuotaHoverReading({
  required final _QuotaHoverEntry entry,
  required final AgentQuotaStatus status,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = _quotaColor(status, entry.remainingPercent);
    final label = _quotaHoverLabel(entry.provider, entry.label);
    final reset =
        _resetText(entry.resetsAt, entry.resetDescription) ??
        'Reset time unavailable';
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                overflow: .ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontWeight: .w500,
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space12),
            Text(
              entry.valueText ?? '${entry.remainingPercent.round()}% Left',
              style: AleraTokens.monoStyle.copyWith(
                fontSize: 11,
                color: color,
                fontWeight: .w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space6),
        if (entry.valueText == null)
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

class const _QuotaHoverEmptyState({required final AgentQuotaSnapshot snapshot})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      snapshot.error == null
          ? 'Quota data unavailable'
          : _normalizeQuotaText(snapshot.error!),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}

class const _QuotaHoverEntry({
  required final AgentQuotaProviderId provider,
  required final String label,
  required final double remainingPercent,
  required final DateTime? resetsAt,
  required final String? resetDescription,
  final String? valueText,
});

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
    for (final amount in snapshot.amounts)
      _QuotaHoverEntry(
        provider: snapshot.provider,
        label: amount.label,
        remainingPercent: 100,
        resetsAt: amount.resetsAt,
        resetDescription: amount.resetDescription,
        valueText: _formatQuotaAmount(amount),
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

String _quotaStatusLabel(AgentQuotaSnapshot snapshot) {
  if (snapshot.status == AgentQuotaStatus.ok &&
      snapshot.dataQuality == 'estimated') {
    return 'Estimated';
  }
  final status = snapshot.status;
  return switch (status) {
    AgentQuotaStatus.ok => 'Live',
    AgentQuotaStatus.stale => 'Stale',
    AgentQuotaStatus.error => 'Error',
    AgentQuotaStatus.unavailable => 'Unavailable',
  };
}
