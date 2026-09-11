import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

enum AleraJobCardStatus { running, failed }

class const AleraJobCard({
  super.key,
  required final String title,
  required final AleraJobCardStatus status,
  final String? phase,
  final String? error,
  final double? progress,
  final VoidCallback? onRetry,
  final VoidCallback? onCancel,
  final VoidCallback? onDismiss,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = status == AleraJobCardStatus.failed;
    final iconColor = failed ? AleraTokens.error : AleraTokens.accent;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AleraTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.border),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: AleraTokens.shadowSoft,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              Row(
                crossAxisAlignment: .start,
                children: <Widget>[
                  if (failed)
                    Icon(AleraIcons.error, size: 16, color: iconColor)
                  else
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: AleraTokens.strokeSm,
                      ),
                    ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (phase case final phase? when phase.trim().isNotEmpty) ...[
                const SizedBox(height: AleraTokens.space8),
                Text(
                  phase,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: AleraTokens.space8),
                LinearProgressIndicator(value: progress!.clamp(0, 1)),
              ],
              if (error case final error? when error.trim().isNotEmpty) ...[
                const SizedBox(height: AleraTokens.space8),
                Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
              ],
              if (onRetry != null || onCancel != null || onDismiss != null) ...[
                const SizedBox(height: AleraTokens.space8),
                Row(
                  mainAxisAlignment: .end,
                  children: <Widget>[
                    if (onDismiss != null)
                      TextButton(
                        onPressed: onDismiss,
                        child: const Text('Dismiss'),
                      ),
                    if (onCancel != null)
                      TextButton(
                        onPressed: onCancel,
                        child: const Text('Cancel'),
                      ),
                    if (onRetry != null)
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
