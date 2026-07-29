part of 'agent_quota_status_bar.dart';

const double _quotaOverviewPanelWidth = 380;
const double _quotaOverviewPanelMaxHeight = 480;

class _QuotaOverviewButton extends StatelessWidget {
  const _QuotaOverviewButton({
    required this.snapshots,
    required this.settings,
    required this.hostId,
    required this.error,
    required this.onTogglePinned,
    required this.profileLabelFor,
  });

  final List<AgentQuotaSnapshot> snapshots;
  final AgentQuotaHostSettings settings;
  final String hostId;
  final String? error;
  final AgentQuotaPinToggle onTogglePinned;
  final String? Function(AgentQuotaSnapshot snapshot) profileLabelFor;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AleraHoverCard(
        semanticsLabel: 'All Agent Quotas',
        card: _AgentQuotaOverviewPanel(
          snapshots: snapshots,
          settings: settings,
          hostId: hostId,
          emptyMessage: error ?? 'No Quota Data',
          onTogglePinned: onTogglePinned,
          profileLabels: <String, String>{
            for (final snapshot in snapshots)
              snapshot.key: ?profileLabelFor(snapshot),
          },
        ),
        child: Container(
          height: AleraTokens.statusBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space6),
          child: const Icon(
            AleraIcons.quota,
            size: 13,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
  }
}

class _AgentQuotaOverviewPanel extends StatelessWidget {
  const _AgentQuotaOverviewPanel({
    required this.snapshots,
    required this.settings,
    required this.hostId,
    required this.onTogglePinned,
    this.profileLabels = const <String, String>{},
    this.emptyMessage = 'No Quota Data',
  });

  final List<AgentQuotaSnapshot> snapshots;
  final AgentQuotaHostSettings settings;
  final String hostId;
  final AgentQuotaPinToggle onTogglePinned;
  final Map<String, String> profileLabels;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _quotaOverviewPanelWidth,
      constraints: const BoxConstraints(
        maxHeight: _quotaOverviewPanelMaxHeight,
      ),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
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
                for (final snapshot in snapshots)
                  _QuotaOverviewRow(
                    snapshot: snapshot,
                    hostId: hostId,
                    profileLabel: profileLabels[snapshot.key],
                    pinned: !settings.unpinnedQuotaKeys.contains(
                      snapshot.pinKey,
                    ),
                    onTogglePinned: onTogglePinned,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotaOverviewRow extends StatelessWidget {
  const _QuotaOverviewRow({
    required this.snapshot,
    required this.hostId,
    required this.profileLabel,
    required this.pinned,
    required this.onTogglePinned,
  });

  final AgentQuotaSnapshot snapshot;
  final String hostId;
  final String? profileLabel;
  final bool pinned;
  final AgentQuotaPinToggle onTogglePinned;

  @override
  Widget build(BuildContext context) {
    final readings = _quotaReadings(snapshot);
    final name = profileLabel == null
        ? snapshot.provider.label
        : '${snapshot.provider.label} $profileLabel';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AgentQuotaProviderIcon(
                provider: snapshot.provider,
                size: 14,
                showTooltip: false,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Tooltip(
                  message: _quotaTooltip(snapshot, profileLabel: profileLabel),
                  waitDuration: AleraTokens.durationMid,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: AleraTokens.monoStyle.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _quotaOverviewNameColor(snapshot.status),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space6),
              if (readings.isEmpty)
                Text(
                  '-',
                  style: AleraTokens.monoStyle.copyWith(
                    fontSize: 10,
                    color: _quotaColor(snapshot.status, null),
                  ),
                )
              else
                for (final (index, reading) in readings.indexed) ...<Widget>[
                  if (index > 0) const SizedBox(width: AleraTokens.space6),
                  Tooltip(
                    message: _quotaTooltipLine(
                      label: reading.fullLabel,
                      remainingPercent: reading.remainingPercent,
                      resetsAt: reading.resetsAt,
                      resetDescription: reading.resetDescription,
                    ),
                    waitDuration: AleraTokens.durationMid,
                    child: _QuotaReadingView(
                      reading: reading,
                      status: snapshot.status,
                      compact: false,
                    ),
                  ),
                ],
              const SizedBox(width: AleraTokens.space6),
              AleraIconButton(
                tooltip: pinned ? 'Unpin From Status Bar' : 'Pin To Status Bar',
                icon: pinned ? AleraIcons.pin : AleraIcons.pinOff,
                iconSize: 12,
                minSize: 22,
                iconColor: pinned
                    ? AleraTokens.foregroundMuted
                    : AleraTokens.foregroundFaint,
                onPressed: () => onTogglePinned(snapshot.pinKey, !pinned),
              ),
            ],
          ),
          if (snapshot.provider == AgentQuotaProviderId.codex &&
              snapshot.rateLimitResetCredits != null)
            _CodexResetCreditsPanel(
              hostId: hostId,
              snapshot: snapshot,
              compact: true,
            ),
        ],
      ),
    );
  }
}

Color _quotaOverviewNameColor(AgentQuotaStatus status) {
  return switch (status) {
    AgentQuotaStatus.ok => AleraTokens.foreground,
    AgentQuotaStatus.stale => AleraTokens.foregroundFaint,
    AgentQuotaStatus.error || AgentQuotaStatus.unavailable => AleraTokens.error,
  };
}
