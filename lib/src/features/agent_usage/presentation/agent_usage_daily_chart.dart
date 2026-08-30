part of 'agent_usage_dialog.dart';

class const AgentUsageDailyChart({
  super.key,
  required final List<AgentUsageDay> days,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox(
        height: AleraTokens.usageChartHeight,
        child: AleraEmptyState(
          title: 'No Daily Activity',
          message: 'No usage was found in this range.',
        ),
      );
    }
    final semanticLabel = days
        .map((day) => '${day.day}: ${day.tokens} tokens')
        .join(', ');
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Semantics(
          label:
              'Daily Claude Code, Codex, and Grok Build token usage. $semanticLabel',
          image: true,
          child: SizedBox(
            height: AleraTokens.usageChartHeight,
            child: _UsageBarChart(days: days),
          ),
        ),
        const SizedBox(height: AleraTokens.space6),
        Row(
          children: <Widget>[
            Text(
              _formatUsageDay(days.first.day),
              style: AleraTokens.monoCompactStyle,
            ),
            const Spacer(),
            const _UsageChartLegend(
              color: AleraTokens.foreground,
              label: 'Claude Code',
            ),
            const SizedBox(width: AleraTokens.space12),
            const _UsageChartLegend(
              color: AleraTokens.foregroundFaint,
              label: 'Codex',
            ),
            const SizedBox(width: AleraTokens.space12),
            const _UsageChartLegend(
              color: AleraTokens.foregroundMuted,
              label: 'Grok Build',
            ),
            const Spacer(),
            Text(
              _formatUsageDay(days.last.day),
              style: AleraTokens.monoCompactStyle,
            ),
          ],
        ),
      ],
    );
  }
}

class const _UsageChartLegend({
  required final Color color,
  required final String label,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        Container(
          width: AleraTokens.space8,
          height: AleraTokens.space8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          ),
        ),
        const SizedBox(width: AleraTokens.space4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class const _UsageBarChart({required final List<AgentUsageDay> days})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final maximum = days.fold<int>(
      1,
      (value, day) => day.tokens > value ? day.tokens : value,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / days.length;
        final groupWidth = (slotWidth - AleraTokens.space2).clamp(
          AleraTokens.space2,
          AleraTokens.space24,
        );
        final barWidth = groupWidth / 5;
        return BarChart(
          BarChartData(
            minY: 0,
            maxY: maximum.toDouble(),
            alignment: .spaceAround,
            barGroups: <BarChartGroupData>[
              for (var index = 0; index < days.length; index++)
                BarChartGroupData(
                  x: index,
                  barsSpace: barWidth,
                  barRods: <BarChartRodData>[
                    _usageBar(
                      days[index].claudeTokens,
                      barWidth,
                      AleraTokens.foreground,
                    ),
                    _usageBar(
                      days[index].codexTokens,
                      barWidth,
                      AleraTokens.foregroundFaint,
                    ),
                    _usageBar(
                      days[index].grokTokens,
                      barWidth,
                      AleraTokens.foregroundMuted,
                    ),
                  ],
                ),
            ],
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maximum / 4,
              getDrawingHorizontalLine: (_) => const FlLine(
                color: AleraTokens.borderSubtle,
                strokeWidth: AleraTokens.strokeHairline,
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AleraTokens.surfaceElevated,
                tooltipBorder: const BorderSide(color: AleraTokens.border),
                tooltipBorderRadius: .circular(AleraTokens.radiusMd),
                tooltipPadding: const .all(AleraTokens.space8),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final provider = _usageProviderLabel(
                    AgentUsageProvider.values[rodIndex],
                  );
                  return BarTooltipItem(
                    '${_formatUsageDay(days[groupIndex].day)}\n$provider: ${_formatUsageTokens(rod.toY.round())}',
                    AleraTokens.monoCompactStyle.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  );
                },
              ),
            ),
          ),
          duration: .zero,
        );
      },
    );
  }
}

BarChartRodData _usageBar(int tokens, double width, Color color) {
  return BarChartRodData(
    toY: tokens.toDouble(),
    width: width,
    color: tokens == 0 ? Colors.transparent : color,
    borderRadius: .circular(AleraTokens.radiusSm),
  );
}
