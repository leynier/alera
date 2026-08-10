part of 'agent_usage_dialog.dart';

class AgentUsageDailyChart extends StatelessWidget {
  const AgentUsageDailyChart({super.key, required this.days});

  final List<AgentUsageDay> days;

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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          label: 'Daily Claude Code and Codex token usage. $semanticLabel',
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

class _UsageChartLegend extends StatelessWidget {
  const _UsageChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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

class _UsageBarChart extends StatelessWidget {
  const _UsageBarChart({required this.days});

  final List<AgentUsageDay> days;

  @override
  Widget build(BuildContext context) {
    final maximum = days.fold<int>(
      1,
      (value, day) => day.tokens > value ? day.tokens : value,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / days.length;
        final pairWidth = (slotWidth - AleraTokens.space2).clamp(
          AleraTokens.space2,
          AleraTokens.space20,
        );
        final barWidth = (pairWidth - AleraTokens.space2) / 2;
        return BarChart(
          BarChartData(
            minY: 0,
            maxY: maximum.toDouble(),
            alignment: BarChartAlignment.spaceAround,
            barGroups: <BarChartGroupData>[
              for (var index = 0; index < days.length; index++)
                BarChartGroupData(
                  x: index,
                  barsSpace: AleraTokens.space2,
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
                tooltipBorderRadius: BorderRadius.circular(
                  AleraTokens.radiusMd,
                ),
                tooltipPadding: const EdgeInsets.all(AleraTokens.space8),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final provider = rodIndex == 0 ? 'Claude Code' : 'Codex';
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
          duration: Duration.zero,
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
    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
  );
}
