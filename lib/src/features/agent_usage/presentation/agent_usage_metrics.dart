part of 'agent_usage_dialog.dart';

class const _UsageMetric({
  super.key,
  required final String label,
  required final String value,
  required final String detail,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: AleraTokens.usageMetricMinHeight,
      ),
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            value,
            style: AleraTokens.monoStyle.copyWith(
              color: AleraTokens.foreground,
              fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
              fontWeight: .w600,
            ),
          ),
          const SizedBox(height: AleraTokens.space2),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundFaint),
          ),
        ],
      ),
    );
  }
}

class const _UsageMetrics({required final List<Widget> metrics})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            ((constraints.maxWidth + AleraTokens.space8) /
                    (AleraTokens.usageMetricMinWidth + AleraTokens.space8))
                .floor()
                .clamp(1, metrics.length);
        final metricWidth =
            (constraints.maxWidth - AleraTokens.space8 * (columns - 1)) /
            columns;
        return Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            for (final metric in metrics)
              SizedBox(width: metricWidth, child: metric),
          ],
        );
      },
    );
  }
}
