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
            child: CustomPaint(
              painter: _AgentUsageDailyChartPainter(days: days),
            ),
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

class _AgentUsageDailyChartPainter extends CustomPainter {
  const _AgentUsageDailyChartPainter({required this.days});

  final List<AgentUsageDay> days;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || size.width <= 0 || size.height <= 0) return;
    final maximum = days.fold<int>(
      1,
      (value, day) => day.tokens > value ? day.tokens : value,
    );
    final grid = Paint()
      ..color = AleraTokens.borderSubtle
      ..strokeWidth = AleraTokens.strokeHairline;
    for (var line = 0; line <= 4; line++) {
      final y = size.height * line / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final slotWidth = size.width / days.length;
    final pairWidth = (slotWidth - AleraTokens.space2).clamp(
      AleraTokens.space2,
      AleraTokens.space20,
    );
    final barWidth = (pairWidth - AleraTokens.space2) / 2;
    final claudePaint = Paint()..color = AleraTokens.foreground;
    final codexPaint = Paint()..color = AleraTokens.foregroundFaint;
    for (var index = 0; index < days.length; index++) {
      final day = days[index];
      final center = (index + 0.5) * slotWidth;
      final left = center - pairWidth / 2;
      _drawUsageBar(
        canvas,
        size.height,
        left,
        barWidth,
        day.claudeTokens / maximum,
        claudePaint,
      );
      _drawUsageBar(
        canvas,
        size.height,
        left + barWidth + AleraTokens.space2,
        barWidth,
        day.codexTokens / maximum,
        codexPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_AgentUsageDailyChartPainter oldDelegate) {
    if (oldDelegate.days.length != days.length) return true;
    for (var index = 0; index < days.length; index++) {
      final old = oldDelegate.days[index];
      final current = days[index];
      if (old.day != current.day ||
          old.claudeTokens != current.claudeTokens ||
          old.codexTokens != current.codexTokens) {
        return true;
      }
    }
    return false;
  }
}

void _drawUsageBar(
  Canvas canvas,
  double height,
  double left,
  double width,
  double share,
  Paint paint,
) {
  if (share <= 0 || width <= 0) return;
  final top = height * (1 - share.clamp(0.0, 1.0));
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(left, top, left + width, height),
      const Radius.circular(AleraTokens.radiusSm),
    ),
    paint,
  );
}
