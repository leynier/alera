import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Compact confirmation modal with a title, supporting copy, and an equal-width
/// Cancel + primary action footer. Pops `true` from the [Navigator] when the
/// primary action is taken and `false` otherwise.
///
/// Pass [destructive] when the action removes data; the primary button then
/// uses the error background so the consequence is visually obvious.
class const AleraConfirmDialog({
  super.key,
  required final String title,
  required final String message,
  required final String confirmLabel,
  final String cancelLabel = 'Cancel',
  final bool destructive = false,
  final bool confirmEnabled = true,
}) extends StatelessWidget {
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
          mainAxisSize: .min,
          crossAxisAlignment: .start,
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
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(cancelLabel, maxLines: 1, overflow: .ellipsis),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: confirmEnabled
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: confirmStyle,
                    child: Text(confirmLabel, maxLines: 1, overflow: .ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
