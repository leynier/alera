import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Compact confirmation modal with a title, supporting copy, and a Cancel +
/// primary action footer. Pops `true` from the [Navigator] when the primary
/// action is taken and `false` otherwise.
///
/// Pass [destructive] when the action removes data; the primary button then
/// uses the error background so the consequence is visually obvious.
class AleraConfirmDialog extends StatelessWidget {
  const AleraConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirmStyle = destructive
        ? FilledButton.styleFrom(
            backgroundColor: AleraTokens.error,
            foregroundColor: AleraTokens.onError,
          )
        : null;
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(cancelLabel),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: confirmStyle,
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
