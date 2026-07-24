part of 'agent_quota_status_bar.dart';

class _QuotaProviderSummary extends StatelessWidget {
  const _QuotaProviderSummary({
    required this.snapshot,
    required this.profileLabel,
    required this.compact,
    required this.hostId,
  });

  final AgentQuotaSnapshot snapshot;
  final String? profileLabel;
  final bool compact;
  final String hostId;

  @override
  Widget build(BuildContext context) {
    final readings = _quotaReadings(snapshot);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AleraHoverCard(
        semanticsLabel: _quotaTooltip(snapshot, profileLabel: profileLabel),
        card: _AgentQuotaHoverCard(
          snapshots: <AgentQuotaSnapshot>[snapshot],
          profileLabels: profileLabel == null
              ? const <String, String>{}
              : <String, String>{snapshot.key: profileLabel!},
          hostId: hostId,
        ),
        child: Container(
          height: AleraTokens.statusBarHeight,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AleraTokens.space6 : AleraTokens.space8,
          ),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AleraTokens.borderSubtle)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AgentQuotaProviderIcon(
                provider: snapshot.provider,
                size: compact ? 12 : 14,
                showTooltip: false,
              ),
              if (profileLabel != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                Text(
                  profileLabel!,
                  style: AleraTokens.monoStyle.copyWith(
                    fontSize: compact ? 8 : 9,
                    color: AleraTokens.foregroundMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                  if (index > 0)
                    SizedBox(
                      width: compact ? AleraTokens.space4 : AleraTokens.space6,
                    ),
                  _QuotaReadingView(
                    reading: reading,
                    status: snapshot.status,
                    compact: compact,
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsedQuotaBar extends StatelessWidget {
  const _CollapsedQuotaBar({
    required this.hostId,
    required this.snapshots,
    required this.settings,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onTogglePinned,
    this.trailing,
  });

  final String hostId;
  final List<AgentQuotaSnapshot> snapshots;
  final AgentQuotaHostSettings settings;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final AgentQuotaPinToggle onTogglePinned;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = snapshots.isEmpty
        ? error ?? 'No Quota Data'
        : snapshots
              .map(
                (snapshot) => _quotaTooltip(
                  snapshot,
                  profileLabel: snapshot.provider == AgentQuotaProviderId.claude
                      ? snapshot.displayName
                      : null,
                ),
              )
              .join('\n\n');
    return Row(
      children: <Widget>[
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AleraHoverCard(
              semanticsLabel: semanticsLabel,
              card: _AgentQuotaOverviewPanel(
                snapshots: snapshots,
                settings: settings,
                emptyMessage: error ?? 'No Quota Data',
                hostId: hostId,
                onTogglePinned: onTogglePinned,
                profileLabels: <String, String>{
                  for (final snapshot in snapshots)
                    if (snapshot.provider == AgentQuotaProviderId.claude)
                      snapshot.key: snapshot.displayName,
                },
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      AleraIcons.agent,
                      size: 13,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Expanded(
                      child: Text(
                        loading
                            ? 'Refreshing Quotas'
                            : '${snapshots.length} Agent Quotas - '
                                  '${hostId == 'local' ? 'Local' : hostId}',
                        overflow: TextOverflow.ellipsis,
                        style: AleraTokens.monoStyle.copyWith(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _QuotaRefreshButton(loading: loading, onRefresh: onRefresh),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

class _QuotaRefreshButton extends StatefulWidget {
  const _QuotaRefreshButton({required this.loading, required this.onRefresh});

  final bool loading;
  final VoidCallback onRefresh;

  @override
  State<_QuotaRefreshButton> createState() => _QuotaRefreshButtonState();
}

class _QuotaRefreshButtonState extends State<_QuotaRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AleraTokens.durationSpin,
    );
    if (widget.loading) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_QuotaRefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.loading && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.loading
          ? 'Refreshing Quotas'
          : 'Refresh Quotas - Automatically Refreshes Every 5 Minutes',
      onPressed: widget.loading ? null : widget.onRefresh,
      iconSize: 13,
      visualDensity: VisualDensity.compact,
      color: AleraTokens.foregroundMuted,
      disabledColor: AleraTokens.foregroundFaint,
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(AleraIcons.refresh),
      ),
    );
  }
}

Color _quotaColor(AgentQuotaStatus status, double? remaining) {
  if (status == AgentQuotaStatus.error ||
      status == AgentQuotaStatus.unavailable) {
    return AleraTokens.error;
  }
  if (status == AgentQuotaStatus.stale) {
    return AleraTokens.foregroundFaint;
  }
  if (remaining == null) {
    return AleraTokens.foregroundFaint;
  }
  if (remaining < 20) {
    return AleraTokens.error;
  }
  if (remaining < 50) {
    return AleraTokens.warning;
  }
  return AleraTokens.success;
}

String _quotaTooltip(
  AgentQuotaSnapshot snapshot, {
  required String? profileLabel,
}) {
  final title = profileLabel == null
      ? snapshot.provider.label
      : '${snapshot.provider.label} - $profileLabel';
  final lines = <String>[title];
  for (final window in snapshot.windows) {
    lines.add(
      _quotaTooltipLine(
        label: window.label,
        remainingPercent: window.remainingPercent,
        resetsAt: window.resetsAt,
        resetDescription: window.resetDescription,
      ),
    );
  }
  for (final bucket in snapshot.buckets) {
    lines.add(
      _quotaTooltipLine(
        label: bucket.name,
        remainingPercent: bucket.remainingPercent,
        resetsAt: bucket.resetsAt,
        resetDescription: bucket.resetDescription,
      ),
    );
  }
  if (snapshot.error case final error?) {
    lines.add('Error: ${_normalizeQuotaText(error)}');
  } else if (!snapshot.hasUsage) {
    lines.add('Quota Data Unavailable');
  }
  return lines.join('\n');
}

String _quotaTooltipLine({
  required String label,
  required double remainingPercent,
  required DateTime? resetsAt,
  required String? resetDescription,
}) {
  final reset =
      _resetText(resetsAt, resetDescription) ?? 'Reset Time Unavailable';
  return '${_normalizeQuotaText(label)}: '
      '${remainingPercent.round()}% Left - $reset';
}

String _normalizeQuotaText(String value) {
  return value
      .replaceAll('-', '-')
      .replaceAll('–', '-')
      .replaceAll(RegExp(r'\bGpt\b'), 'GPT');
}

String? _resetText(DateTime? resetsAt, String? description) {
  if (resetsAt != null) {
    return 'Resets In ${_compactResetDuration(resetsAt.difference(DateTime.now()))}';
  }
  if (description != null && description.trim().isNotEmpty) {
    final duration = _durationFromResetDescription(description);
    if (duration != null) {
      return 'Resets In ${_compactResetDuration(duration)}';
    }
    return _normalizeQuotaText(description.trim());
  }
  return null;
}

Duration? _durationFromResetDescription(String description) {
  final lower = description.toLowerCase();
  if (!lower.contains(' in ')) {
    return null;
  }
  var minutes = 0;
  final matches = RegExp(
    r'(\d+)\s*(days?|d|hours?|hrs?|h|minutes?|mins?|m)\b',
  ).allMatches(lower);
  for (final match in matches) {
    final value = int.tryParse(match.group(1) ?? '');
    final unit = match.group(2);
    if (value == null || unit == null) {
      continue;
    }
    if (unit.startsWith('d')) {
      minutes += value * Duration.minutesPerDay;
    } else if (unit.startsWith('h')) {
      minutes += value * Duration.minutesPerHour;
    } else {
      minutes += value;
    }
  }
  return minutes == 0 ? null : Duration(minutes: minutes);
}

String _compactResetDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '<1m';
  }
  final totalMinutes = (duration.inSeconds / Duration.secondsPerMinute).ceil();
  final days = totalMinutes ~/ Duration.minutesPerDay;
  final hours =
      (totalMinutes % Duration.minutesPerDay) ~/ Duration.minutesPerHour;
  final minutes = totalMinutes % Duration.minutesPerHour;
  return <String>[
    if (days > 0) '${days}d',
    if (hours > 0) '${hours}h',
    if (minutes > 0 || days == 0 && hours == 0) '${minutes}m',
  ].join(' ');
}
