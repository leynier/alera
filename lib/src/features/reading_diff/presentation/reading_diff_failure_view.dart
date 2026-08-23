import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

class ReadingDiffFailureView extends StatelessWidget {
  const ReadingDiffFailureView({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: AleraTokens.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: AleraTokens.space2),
              child: Icon(
                AleraIcons.error,
                size: AleraTokens.space16,
                color: AleraTokens.error,
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Reading diff generation failed',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AleraTokens.error,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space2),
                  SelectableText(message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Dismiss Error',
              icon: AleraIcons.close,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
