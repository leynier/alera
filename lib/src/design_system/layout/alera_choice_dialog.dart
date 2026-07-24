import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Compact modal with a title, supporting copy, a cancel action, a primary
/// action, and an optional secondary action.
///
/// Pops [primaryValue] / [secondaryValue] / `null` (cancel) from the
/// [Navigator]. Pass [destructiveSecondary] when the secondary action removes
/// or terminates work so it uses the error button style.
class AleraChoiceDialog<T> extends StatelessWidget {
  const AleraChoiceDialog({
    super.key,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryValue,
    this.cancelLabel = 'Cancel',
    this.secondaryLabel,
    this.secondaryValue,
    this.destructiveSecondary = false,
  });

  final String title;
  final String message;
  final String primaryLabel;
  final T primaryValue;
  final String cancelLabel;
  final String? secondaryLabel;
  final T? secondaryValue;
  final bool destructiveSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryStyle = destructiveSecondary
        ? FilledButton.styleFrom(
            backgroundColor: AleraTokens.error,
            foregroundColor: AleraTokens.onError,
          )
        : null;
    final hasSecondary =
        secondaryLabel != null && secondaryValue != null;
    return AleraDialog(
      maxWidth: 440,
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
            if (hasSecondary) ...<Widget>[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(secondaryValue as T),
                  style: secondaryStyle,
                  child: Text(
                    secondaryLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: AleraTokens.space8),
            ],
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      cancelLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(primaryValue),
                    child: Text(
                      primaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
