import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

enum AleraInlineNoticeTone { info, warning, error }

/// Bordered callout that sits inside a form next to the field it explains: a
/// tone icon, a sentence of [message], and an optional [child] below it for
/// the controls that resolve the situation.
class const AleraInlineNotice({
  super.key,
  required final String message,
  final AleraInlineNoticeTone tone = .info,
  final Widget? child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (tone) {
      .info => (AleraIcons.info, AleraTokens.info),
      .warning => (AleraIcons.warning, AleraTokens.warning),
      .error => (AleraIcons.warning, AleraTokens.error),
    };
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space2),
                child: Icon(icon, size: AleraTokens.iconMd, color: color),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ],
          ),
          if (child case final child?) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            child,
          ],
        ],
      ),
    );
  }
}
