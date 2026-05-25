import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Base modal scaffold with Alera's surface, inset padding, radius and subtle
/// border. Optionally constrains the content via [maxWidth] / [maxHeight].
class AleraDialog extends StatelessWidget {
  const AleraDialog({
    super.key,
    required this.child,
    this.maxWidth,
    this.maxHeight,
    this.backgroundColor,
    this.insetPadding,
  });

  final Widget child;
  final double? maxWidth;
  final double? maxHeight;
  final Color? backgroundColor;
  final EdgeInsets? insetPadding;

  @override
  Widget build(BuildContext context) {
    final constrained = (maxWidth != null || maxHeight != null)
        ? ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth ?? double.infinity,
              maxHeight: maxHeight ?? double.infinity,
            ),
            child: child,
          )
        : child;
    return Dialog(
      backgroundColor: backgroundColor ?? AleraTokens.surface,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(
            horizontal: AleraTokens.space32,
            vertical: AleraTokens.space32,
          ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
        side: const BorderSide(color: AleraTokens.borderSubtle),
      ),
      child: constrained,
    );
  }
}
