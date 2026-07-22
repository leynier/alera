import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
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
    this.elevation,
  });

  final Widget child;
  final double? maxWidth;
  final double? maxHeight;
  final Color? backgroundColor;
  final EdgeInsets? insetPadding;
  final double? elevation;

  @override
  Widget build(BuildContext context) {
    var constrained = child;
    if (maxWidth != null || maxHeight != null) {
      constrained = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? double.infinity,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: child,
      );
    }
    return Dialog(
      backgroundColor: backgroundColor ?? AleraTokens.surface,
      elevation: elevation,
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
