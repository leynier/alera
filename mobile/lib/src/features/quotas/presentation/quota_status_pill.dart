import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class const QuotaStatusPill({super.key, required final String status})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ok' => AleraTokens.success,
      'stale' => AleraTokens.warning,
      _ => AleraTokens.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.spaceSm,
        vertical: AleraTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AleraTokens.emphasisOverlayAlpha),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: Text(
        status == 'ok'
            ? 'Live'
            : status == 'stale'
            ? 'Stale'
            : 'Unavailable',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
