import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Small pill label used to tag a row.
class const AleraBadge({
  super.key,
  required final String label,
  final Color? color,
  final Color? foregroundColor,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: color ?? AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: .ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foregroundColor ?? AleraTokens.foregroundMuted),
      ),
    );
  }
}
