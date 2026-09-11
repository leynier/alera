import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

enum AleraJobCardStatus { running, failed }

class const AleraJobCard({
  super.key,
  required final String title,
  required final AleraJobCardStatus status,
  final String? phase,
  final String? error,
  final VoidCallback? onRetry,
  final VoidCallback? onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = status == AleraJobCardStatus.failed;
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (failed)
                  const Icon(Icons.error_outline, color: AleraTokens.error)
                else
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: AleraTokens.spaceSm),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            if (phase case final phase?) ...[
              const SizedBox(height: AleraTokens.spaceSm),
              Text(phase, style: theme.textTheme.bodySmall),
            ],
            if (error case final error?) ...[
              const SizedBox(height: AleraTokens.spaceSm),
              Text(error, style: const TextStyle(color: AleraTokens.error)),
            ],
            if (onRetry != null || onDismiss != null)
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: .min,
                  children: <Widget>[
                    if (onDismiss != null)
                      TextButton(
                        onPressed: onDismiss,
                        child: const Text('Dismiss'),
                      ),
                    if (onRetry != null)
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
