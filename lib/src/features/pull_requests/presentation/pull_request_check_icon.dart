import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:flutter/material.dart';

/// Presentational icon for a single check's status/conclusion. Pure: derives an
/// icon and token color from [status] and [conclusion] with no Riverpod reads.
class PullRequestCheckIcon extends StatelessWidget {
  const PullRequestCheckIcon({
    super.key,
    required this.status,
    required this.conclusion,
    this.size = 16,
  });

  final ReviewCheckStatus status;
  final ReviewCheckConclusion conclusion;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconAndColor();
    return Icon(icon, size: size, color: color);
  }

  (IconData, Color) _iconAndColor() {
    if (status != ReviewCheckStatus.completed ||
        conclusion == ReviewCheckConclusion.pending) {
      return (AleraIcons.loading, AleraTokens.warning);
    }
    return switch (conclusion) {
      ReviewCheckConclusion.success => (
        AleraIcons.success,
        AleraTokens.success,
      ),
      ReviewCheckConclusion.failure ||
      ReviewCheckConclusion.cancelled ||
      ReviewCheckConclusion.timedOut ||
      ReviewCheckConclusion.actionRequired => (
        AleraIcons.cancel,
        AleraTokens.error,
      ),
      ReviewCheckConclusion.neutral || ReviewCheckConclusion.skipped => (
        AleraIcons.circle,
        AleraTokens.foregroundMuted,
      ),
      ReviewCheckConclusion.pending => (
        AleraIcons.loading,
        AleraTokens.warning,
      ),
    };
  }
}
